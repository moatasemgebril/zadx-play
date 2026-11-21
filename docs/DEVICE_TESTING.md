# Device testing — how Zad X Play is tested on real devices

The ZADX Team's sandbox has no Flutter SDK and no phones, so real builds and device tests run in the cloud:

| Step | Where | What it checks |
|---|---|---|
| analyze + unit tests | GitHub Actions (Linux) | code errors, prayer-time and wallet logic |
| Android APK build | GitHub Actions | the app compiles; the APK is downloadable from the run page |
| Android emulator | GitHub Actions | the app installs, launches and survives 300 random taps |
| Real phones | Firebase Test Lab (when `GCP_SA_KEY` is set) | Robo test on real Pixel/Samsung devices, Arabic + English |
| iOS build | GitHub Actions (macOS) | the iOS app compiles (no signing) |
| Backend | GitHub Actions | Cloud Functions compile, `npm audit` has no high/critical issues |
| Windows Guard | GitHub Actions (Windows) | the C# service builds |

## When each check runs (owner decision 2026-11-20: save GitHub Actions minutes)
| Event | What runs |
|---|---|
| Pull request | light checks only: analyze, unit tests, Android APK, web build, backend |
| Merge to `main` | light checks + the heavy job only for what changed (emulator if `lib/`/`android/`/`assets/`/`pubspec` changed, iOS if `ios/` changed, Windows if `windows_guard/` changed) |
| Nightly Mon–Sat (~2–3 AM Pacific) | light checks + emulator + 300 taps — skipped if `main` had no commits in the last ~25 h |
| Weekly, Sunday (~2–3 AM Pacific) | everything: emulator, iOS, Windows, real phones — skipped if `main` had no commits in 8 days |
| "Run workflow" (manual) | everything |
| Docs only (`*.md`, `docs/`, `reports/`) | nothing |

Merge rule: a PR merges when its light checks are green and the Quality Gate approves. If the nightly or `main` heavy run fails, fixing it is P0 in the next morning cycle, and no new features merge until it is green again.
Artifacts (APK, coverage) are kept 7 days. Caches: Flutter/pub, Gradle, npm.
Why iOS is weekly: the owner keeps GitHub's free plan with a $0 spending limit (≈2,000 min/month); macOS minutes count ×10 and Windows ×2.

## One-time setup by the owner
1. Create a free GitHub account and a **private** repository `zadx-play`, and upload this project (or connect GitHub to Claude so the team can push it).
2. (Optional, real phones) In Firebase → Test Lab, create a service account with the "Firebase Test Lab Admin" role, and add its JSON key as the repository secret `GCP_SA_KEY`.
3. To try the app on your own Android phone: open the latest run under **Actions**, download `zadx-android-apk`, and install it.

Still needs humans: the app-lock features (Accessibility on Android, Screen Time on iOS, the Windows service) must be tried by hand on a real device before launch.
