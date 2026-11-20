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

## Multiple children (next step)
`activeChildIdProvider` is fixed to `child-1`. To support Basic (2) / Plus (5) children: add a
`children` collection with names/avatars, a child picker on the parent dashboard, and pass the
selected child id to `WalletController`, pairing (`childId` on the device) and the guard.

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
