# Architecture

## Principles
- **One source of truth for play time:** `WalletController` (`lib/features/tasks/wallet_controller.dart`).
  UI and native code only read `WalletState`; every change goes through the controller.
- **Native code enforces, Dart decides:** Dart computes a `LockPolicy` (locked?, reason, mode, games,
  allow-list, minutes) and pushes it over `com.zadx.app/app_lock`. Default mode `allApps` locks every app
  except an always-allowed core + the parent's allow-list (docs/decisions/DEVICE-WIDE-LOCK.md);
  `selectedGames` is the legacy block-list. Native blockers keep enforcing it when the
  app is closed (Android `LockStore` + AccessibilityService; iOS ManagedSettings + DeviceActivity).
- **No secrets in the app:** AI and store verification run in Cloud Functions.
- **No hand-typed Quran:** surah metadata only; text comes from Quran.com and is cached.
- **Offline-first:** the child side works without internet; Firebase syncs, it is never required (see "Offline-first" below).

## Flow of a day
```
Parent sets tasks ─┐
                   ▼
Child taps "Done" / counts reps / finishes adhkar ──► status = pending ──► parent notified
                                                                        │
Parent approves (PIN, parent phone) ◄───────────────────────────────────┘
        │  synced family: approveTask callable (server checks the PARENT role, credits once, daily cap)
        ▼
earnedMinutes ↑ ─► gamesUnlocked = requiredDone && !prayerLock && remaining > 0
        │
        ▼
LockPolicy ─► native: unshield games, count minutes (Android per minute / iOS threshold)
        │
Adhan time ─► WalletController.startPrayerLock  (+ native alarm/DeviceActivity if app closed)
        │        child taps "I prayed" ─► pending ─► parent approves ─► lock lifted
        ▼
Next day ─► progress resets, task definitions stay
```

## State management
Riverpod 2 (`Notifier`/`Provider`). Key providers:
| Provider | Role |
|---|---|
| `settingsProvider` | language, city, method, muezzin, reciter, controlled games, PIN hash |
| `prayerTimesProvider` / `nextPrayerProvider` | computed from settings + city clock |
| `walletProvider` | tasks, approvals, minutes, prayer lock |
| `lockPolicyProvider` / `lockCoordinatorProvider` | bridge to native blockers |
| `playerProvider` | adhan + Quran audio |
| `adhkarProvider` | daily tasbeeh counts → submits adhkar tasks |
| `entitlementProvider` | Free / Basic / Plus / trial (trial = Plus) |

## Family sync & pairing
`FamilyRepository` has a local and a Firestore implementation, chosen by `familyIdProvider`.
On first launch the device signs in anonymously and creates a family.

Pairing (`lib/services/family/pairing_service.dart`, Cloud Functions `createPairingCode` /
`redeemPairingCode`):
1. Parent → *Link devices* → picks "child's phone" or "Windows PC" → 6-digit code (10 min, single use).
2. Child phone → Language & location screen → *Have a link code?* → joins the family
   (its uid is added to `members`; the wallet re-subscribes to the shared day document).
3. Windows PC → `install.ps1 -PairingCode …` → the guard receives a device id + secret.

All devices share `families/{id}/children/{childId}/days/{yyyy-MM-dd}`.

### Task approval (server-side, R-32)
Approval is decided by the server, not by the PIN on a phone:

| Who | May write on `days/{day}` | Never |
|---|---|---|
| Child device (bound in `childDevices`, server-written) | `progress` (submissions: status `pending`, rep counts), `usedMinutes` **up only** (sent as `FieldValue.increment`), start a prayer lock (`prayerLock: true` + `prayerLockAt` = server time), end it only after the Free window (19 min after `prayerLockAt`) | `approved`, `earnedMinutes`, `requiredDone`; delete the day; another child's docs |
| Parent device (member, not bound) | `progress`, `usedMinutes`, `prayerLock` | `approved`, `earnedMinutes`, `requiredDone` (only via `approveTask`) |
| `approveTask` Cloud Function | `approved.{taskId}` (minutes, once per task per day, ≤ 120 per task, ≤ 600 per day), `earnedMinutes`, `requiredDone`, `progress.{taskId} = done`, ends the prayer lock for "I prayed" | — |

1. Child taps *Done* / counts reps / *I prayed* → `progress.{taskId}.status = pending` (works offline:
   Firestore queues the write) → `notifyParent`.
2. Parent opens the parent dashboard (PIN) on a **parent phone** → *Approve* → `approveTask`
   (`rejectTask` for *Reject*). The server reads the family doc and refuses any device listed in
   `childDevices` (role from server data, never from client claims) and runs the credit in a transaction.
3. Offline parent: the decision shows at once on that phone and waits in `ApprovalQueue`
   (`lib/services/family/approval_queue.dart`, shared_preferences); it is sent when the wallet
   rebuilds / the next decision is made online. Permanent refusals are dropped, never retried forever.
4. Every device applies the result from the day doc: in a synced family a task counts only with an
   `approved` entry (`WalletState.isApproved`), so a "done" status written by a tampered child client
   earns nothing. Local-only families (no Firebase) keep approving on the device behind the PIN.
5. A paired child device cannot approve even with the PIN: the dashboard shows
   "Approve tasks from the parent phone".

Family `settings` (adhan lock, controlled games, lock mode, time zone, parent pushes) are
**parent-only** (R-33): only parent devices write the family doc; `_syncSettings` in `lib/app.dart`
is skipped on a bound child device, and the parent phone writes the defaults on its first start.

### Family plan & restore on a new phone (fix/family-entitlement-restore)
- **Plan on every family device.** `verifyPurchase` writes `plan`, `planExpiresAt` (ISO string),
  `inTrial`, `store` on `families/{id}` (server-only fields, readable by every member, child
  devices included). `FamilyRepository.watchEntitlement()` streams them (server-confirmed
  snapshots only, never the offline cache; local mode emits nothing). `planEntitlementProvider`
  takes the highest active tier of this device's own verified purchase and the family doc, then
  the `EntitlementCache` grace (7 days offline, clock-rollback safe), then the device trial, then
  Free. Every new server answer (including "expired") is recorded in the cache once, by
  `entitlementRecorderProvider`.
- **The raw store token is server-only.** Ownership lives in `purchases/{sha256(token)}` →
  `familyId` (first attach uses a transaction with `create()`, so two racing first purchases
  cannot both win); the raw token (for referral deferrals) in `families/{id}/private/billing`.
  Both are closed to clients in firestore.rules. Existing family docs are migrated once with
  `backend/functions/scripts/migrate-purchase-tokens.js` (run at deploy, see backend/README.md).
- **Restore on a new phone = link it from an existing parent phone.** The store token is a
  bearer secret (`restorePurchases()` gives it to any device on that store account, a child's
  tablet included), so it never grants membership or the plan: a token held by another family
  makes `verifyPurchase` fail with `purchase_in_other_family`, and the subscription screen
  (behind the parent PIN) explains: on the other parent phone open Parent → Link devices →
  "Add a parent phone", then enter the code here. `createPairingCode` target `parent` is
  accepted only from a parent member (not `childDevices`), same 6 digits / 10 min / single use,
  plus 5 parent codes per family per day. Redeeming it adds the phone to `members` and the
  server-only `parentDevices` map; the phone's own family must be an untouched fresh install and
  is deleted (otherwise `parent_link_family_in_use`, so no data is abandoned); a child-bound
  device is refused (`child_device`). Existing parent phones get a push. The app saves
  `family.id`, switches `familyIdProvider` and re-runs the store restore, which now attaches.
  Removing a linked device is still open (BACKLOG P1-3).

## Platforms
| Platform | Game locking | Everything else |
|---|---|---|
| Android | AccessibilityService (this app) | ✓ |
| iOS / iPadOS | Screen Time API (this app + 2 extensions) | ✓ |
| Windows | **Zad X Guard** service (`windows_guard/`) using `devicePolicy` / `reportUsage` | ✓ dashboard |
| macOS | not yet (study) | ✓ dashboard |
| Web | — | ✓ dashboard |
| PlayStation / Xbox | no public API → parent alerts + deep link to PlayStation Family / Microsoft Family Safety, plus suggested play windows between prayers | — |

## Plans: Free / Basic / Plus (owner request 2026-11-21)
Single source of truth: `lib/data/models/plan.dart` (`AppFeature`, `featuresOf`, `hasFeature`),
mirrored in `backend/functions/src/security.ts` (`PLAN_FEATURES`); `test/plan_matrix_test.dart`
fails if the two differ. Free = no store purchase (`Entitlement.effectiveTier == null`); a trial is Plus.

| Feature | Free (مجاني للأبد) | Basic (أساسي) | Plus (بلس) |
|---|---|---|---|
| App lock: prayer-time lock + daily time limit | ✓ (1 child) | ✓ | ✓ |
| Prayer times | ✓ | ✓ | ✓ |
| Adhan (all voices) | ✓ | ✓ | ✓ |
| Quran (approved reciters) | ✓ | ✓ | ✓ |
| Tasks & rewards wallet | — | ✓ | ✓ |
| Games that unlock after tasks/timer | — | ✓ (5) | ✓ (15) |
| Zad X learning games | — | ✓ | ✓ |
| Exercises | — | ✓ | ✓ |
| Adhkar | — | ✓ | ✓ |
| Custom unlock tasks | — | ✓ | ✓ |
| Children | 1 | 2 | 5 |
| Parent assistant | — | 10/day | 100/day |
| PlayStation / Microsoft family links | — | — | ✓ |
| Weekly parent report | — | — | ✓ |

Free features never need login, network or purchase. Paid screens show a kid-safe
"ask a parent" card; the upgrade sheet and the plans screen sit behind the parent PIN.

## Multiple children
Free = 1 child, Basic = up to 2, Plus = up to 5 (`PlanPricing.maxChildren`).

- **Profile** (`lib/data/models/child_profile.dart`): random id, nickname, built-in avatar.
  No birthdate, photo or last name (COPPA / GDPR-K data minimisation); nicknames that look
  like e-mails or phone numbers are rejected.
- **On device** (`lib/services/family/children_controller.dart`, `child_storage.dart`):
  `childrenProvider` holds the list, the active child and — on a paired child device — the
  bound child. `activeChildIdProvider` drives `WalletController` and `AdhkarController`, so each
  child has its own tasks, minutes and prayer lock (`wallet.child.<id>.*`). The first launch
  after the update moves the old single-child keys into `child-1` (idempotent migration).
- **Parent dashboard** (`lib/features/parent/children_card.dart`): list with per-child summary,
  switch, add (plan limit → upsell), edit, remove (confirmation; deletes local + synced data).
- **Sync**: `families/{id}/children/{childId}` = `{nickname, avatar, updatedAt}`; days below it.
  Pairing codes carry a `childId`; redeeming binds the phone via `families/{id}.childDevices[uid]`
  (Cloud Functions only) and Windows guards via `devices/{id}.childId`.
- **Rules**: a member without a `childDevices` entry is a parent and can manage every child; a
  bound child device can read only its own child doc and read/write only its own days, and may
  update only `settings` on the family doc. `members` / `childDevices` are server-only.
- On a device that is not bound, the active child's wallet also drives the device game lock.

## Built-in learning games
`lib/features/edu_games/` (plain Flutter widgets + CustomPainter, routes `/edu/<id>`):
- **Quran Letters** (`letters/`): 28 letters, 5 levels (name↔letter, look-alikes, letter shapes).
- **Heroes of the Prophets** (`prophets/`): story quiz; content in `data/catalog/prophets_quiz.dart`
  (`reviewedByScholar = false` until a scholar signs off; prophets are never depicted).
- **Build Your Mosque** (`mosque/`): spends stars on parts, progress in shared_preferences.

Rounds award **stars** (`starsProvider`), a separate cosmetic currency: stars never add play
minutes and never touch `WalletController`, so the game-time lock can't be bypassed here.
Sound/haptic hooks: override `eduGameHooksProvider` (`onCorrect`, `onWrong`, `onRoundComplete`,
`onPartBuilt`; no-ops by default).

## Localization
ARB files in `lib/l10n` (Arabic is the template). Add `fr`, `tr`, `ur`, `id` by creating
`app_<code>.arb` and moving the code from `upcomingLanguages` to `supportedLanguages`.

## Offline-first (owner decision 2026-11-21)
Rule: **the child side works fully without internet.** Firebase is for sync, never a
precondition. A missing connection is never a blocking error on a child screen; parents see a
small offline indicator only.

### What runs on the device
| Area | Target | Today (audit 2026-11-21) |
|---|---|---|
| Prayer times | Computed on-device from saved coordinates | **Already offline.** `PrayerCalculator` (pure Dart, PrayTimes.org formulas) uses the lat/lng of the city picked from `lib/data/catalog/locations.dart`; time zones come from the bundled `timezone` database (`latest_all`, initialised in `main.dart`). No network call. `geolocator` is in `pubspec.yaml` but not used anywhere in `lib/`. |
| Adhan audio + notifications | Bundled licensed recordings; local notifications | Code plays `AudioSource.asset(...)` and schedules local notifications (no network). **Gap:** the four `assets/audio/adhan_*.mp3` files are not in the repo yet (only `README.txt`), pending a recordings licence (see `security/APPROVALS-TRACKER.md`). |
| Quran text | Bundled verified Uthmani text | **Needs network on first open of each surah.** `QuranRepository` fetches `api.quran.com/api/v4/quran/verses/uthmani` and then caches in `shared_preferences`. Plan: bundle a verified Uthmani text asset with its required attribution (source and licence to be chosen with the Islamic Content Reviewer; never typed by hand), keep the API as the update path. To verify: whether `api.quran.com/api/v4` is covered by the Quran Foundation approval or we must switch to the QF API with production credentials. |
| Adhkar | Bundled | Already bundled in `lib/data/catalog/adhkar.dart` (scholar review still pending). |
| Quran recitation audio | May stream; optional "download for offline" | Streams per ayah from `everyayah.com`. Quran Foundation approved its **recitations API** for Alafasy, Abdul Basit (murattal), Al-Husary and Al-Minshawi (murattal), with **no rehosting on our servers** and downloads allowed **to the user's own device** (BACKLOG.md). Plan: switch the source to the QF API, add "download for offline" for licensed reciters only, stored in app storage on the device. Unlicensed reciters are never downloadable. |
| Games, tasks, unlock timer, lock state | Local DB, enforced locally | Today in `shared_preferences` (`WalletController`) + native stores (`LockStore`, iOS `SharedStore`). Enforcement is already local. |
| Entitlement | Last verified plan with offline grace | `EntitlementCache` (`lib/services/billing/entitlement_cache.dart`): last server-verified tier kept 7 days, then free; clock-rollback guarded. Not wired yet. |

### Local database
Recommendation: **drift** (SQLite; typed queries, migrations, transactions, easy unit tests with an
in-memory database). Licence: drift is MIT, SQLite is public domain (to verify at adoption).
Alternative: Hive — Apache-2.0, simpler key/value boxes, but no relational queries and the original
`hive` 2.x package is lightly maintained (community fork `hive_ce`, to verify). Use drift for
tasks / progress / unlock timer / lock state / command queue; keep `shared_preferences` for small
settings. Lock state stays mirrored to the native stores so it is enforced when the app is closed.

### Sync (Firebase)
- **Firestore offline persistence** on (default on Android/iOS; must be enabled explicitly on web
  — to verify for the current `cloud_firestore` version). Child writes are queued while offline.
- **Queued parent commands** (`families/{id}/children/{childId}/commands/{id}`: lock, unlock, add
  minutes, change limits) carry `issuedAt` (server timestamp) and a parent device id. Task approval
  already goes through the `approveTask` callable (see "Task approval" above).
  The child device applies them in order when it sees them and records `appliedAt` locally.
- **Child progress** (task status, used minutes) is written locally first, then synced.
- **Conflict rule:** for locks and limits, **the parent's latest command wins** (ordered by server
  `issuedAt`). A child-side change never overrides a newer parent command. Progress counters merge
  by taking the max per field for the same day; approvals stay parent-only (risk R-03).
- Until a command reaches the child device, the last known rules keep being enforced locally.

### UX rules
- Child screens: no spinner-forever, no "no internet" error dialogs. Content that truly needs the
  network (streaming a non-downloaded recitation) shows a gentle, non-blocking message and the
  rest of the screen keeps working.
- Parent dashboard: a small "offline — changes will sync" indicator; queued commands shown as
  pending.

### Tests
- Unit tests stay pure (no network): prayer calculator, entitlement cache, wallet, lock policy.
- Add an "offline" test suite that runs with networking disabled (e.g. `HttpOverrides` that throw
  on any connection, plus a fake `FamilyRepository`) and asserts every child screen renders and
  the lock is still enforced.
