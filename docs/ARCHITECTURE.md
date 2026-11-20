# Architecture

## Principles
- **One source of truth for play time:** `WalletController` (`lib/features/tasks/wallet_controller.dart`).
  UI and native code only read `WalletState`; every change goes through the controller.
- **Native code enforces, Dart decides:** Dart computes a `LockPolicy` (locked?, reason, games,
  minutes) and pushes it over `com.zadx.app/app_lock`. Native blockers keep enforcing it when the
  app is closed (Android `LockStore` + AccessibilityService; iOS ManagedSettings + DeviceActivity).
- **No secrets in the app:** AI and store verification run in Cloud Functions.
- **No hand-typed Quran:** surah metadata only; text comes from Quran.com and is cached.

## Flow of a day
```
Parent sets tasks ─┐
                   ▼
Child taps "Done" / counts reps / finishes adhkar ──► status = pending ──► parent notified
                                                                        │
Parent approves (PIN) ◄─────────────────────────────────────────────────┘
        │
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
| `entitlementProvider` | Basic / Plus / trial |

## Family sync & pairing
`FamilyRepository` has a local and a Firestore implementation, chosen by `familyIdProvider`.
On first launch the device signs in anonymously and creates a family.

Pairing (`lib/services/family/pairing_service.dart`, Cloud Functions `createPairingCode` /
`redeemPairingCode`):
1. Parent → *Link devices* → picks "child's phone" or "Windows PC" → 6-digit code (10 min, single use).
2. Child phone → Language & location screen → *Have a link code?* → joins the family
   (its uid is added to `members`; the wallet re-subscribes to the shared day document).
3. Windows PC → `install.ps1 -PairingCode …` → the guard receives a device id + secret.

All devices share `families/{id}/children/{childId}/days/{yyyy-MM-dd}`; the phone also writes the
derived `earnedMinutes` / `requiredDone` so other devices apply identical rules.

## Platforms
| Platform | Game locking | Everything else |
|---|---|---|
| Android | AccessibilityService (this app) | ✓ |
| iOS / iPadOS | Screen Time API (this app + 2 extensions) | ✓ |
| Windows | **Zad X Guard** service (`windows_guard/`) using `devicePolicy` / `reportUsage` | ✓ dashboard |
| macOS | not yet (study) | ✓ dashboard |
| Web | — | ✓ dashboard |
| PlayStation / Xbox | no public API → parent alerts + deep link to PlayStation Family / Microsoft Family Safety, plus suggested play windows between prayers | — |

## Multiple children
Basic = up to 2 children, Plus = up to 5 (`PlanPricing.maxChildren`).

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
