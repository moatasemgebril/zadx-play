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

## One-time setup by the owner
1. Create a free GitHub account and a **private** repository `zadx-play`, and upload this project (or connect GitHub to Claude so the team can push it).
2. (Optional, real phones) In Firebase → Test Lab, create a service account with the "Firebase Test Lab Admin" role, and add its JSON key as the repository secret `GCP_SA_KEY`.
3. To try the app on your own Android phone: open the latest run under **Actions**, download `zadx-android-apk`, and install it.

Still needs humans: the app-lock features (Accessibility on Android, Screen Time on iOS, the Windows service) must be tried by hand on a real device before launch.
