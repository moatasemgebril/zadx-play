# Zad X Play — Add-ons Registry

Owner: zadx-tooling-lead · Last refreshed: 2026-11-21 (branch `cycle/2026-11-21-pm`) · Status: **draft, awaiting Quality Gate**

Every third-party package, action, native dependency, bundled asset and external service the project
depends on, with licence and risk. Zad X Play is a **children's app**: anything that sends data off the
child's device, adds ads/analytics, or ships third-party content is treated as a child-safety / privacy
risk first (COPPA, GDPR-K, Google Play Families, Apple Kids category).

**How this was built:** read from the real files (`pubspec.yaml`, `backend/functions/package.json`,
`.github/workflows/*.yml`, `windows_guard/ZadXGuard.csproj`, `android/`, `ios/`, `assets/**`,
`lib/**`, `backend/functions/src/index.ts`). Usage counts = files in `lib/` that import the package.

**Licence column:** there is no `pubspec.lock`, no `~/.pub-cache` and no `node_modules` in this
environment, so no LICENSE file could be read. Licences below are from the publishers' pub.dev / npm /
NuGet / GitHub listings as known to the team and are marked **(listing)**; anything we are not sure of
is marked **unverified**. Before release, confirm each with `flutter pub deps` + the package's LICENSE
(e.g. `dart pub global run` a licence checker, or Flutter's `LicenseRegistry` output in the app's
"Licences" page).

Risk scale: **Low** = no data leaves the device / build-only · **Med** = network or permission surface,
or licence/attribution duty · **High** = child data / child-facing network call / pre-launch blocker.

---

## 1. Flutter / Dart packages (`pubspec.yaml`)

No `pubspec.lock` is committed (app projects should commit it so builds are reproducible and auditable).
No ads SDK, no analytics SDK (no `firebase_analytics`, `firebase_crashlytics`, Sentry, AdMob) is declared. Good.

| Package | Constraint | Purpose | Licence | Used in lib/ | Data / network on child side | Risk | Action |
|---|---|---|---|---|---|---|---|
| flutter, flutter_localizations | sdk | Framework, AR/EN localisation | BSD-3-Clause | yes | No | Low | — |
| intl | `any` | Dates/numbers, gen-l10n | BSD-3-Clause (listing) | via gen-l10n | No | Low | Replace `any` with a caret range matching the Flutter SDK pin (unbounded constraint). |
| flutter_riverpod | ^2.6.1 | State management | MIT (listing) | yes | No | Low | — |
| go_router | ^14.6.0 | Navigation | BSD-3-Clause (listing) | 11 files | No | Low | — |
| shared_preferences | ^2.3.3 | Local settings + Quran text cache | BSD-3-Clause (listing) | 10 files | No (local only; not encrypted) | Low | Keep PIN hash / child data out of it, or note in privacy policy. |
| ~~google_fonts~~ | removed | — | — | none | **No — package removed 2026-11-23 (branch `fix/bundled-fonts`, pending CI + Quality Gate).** Fonts are bundled under `flutter: fonts:`; `test/bundled_fonts_test.dart` fails if google_fonts returns. | Low | — |
| just_audio | ^0.9.42 | Adhan + Quran playback | MIT (listing) | 2 files | Streams Quran audio from everyayah.com (see §6) | Med | Source change tracked as R-34. |
| just_audio_windows | ^0.2.2 | Windows backend for just_audio | **unverified** (believed MIT) | federated plugin (no direct import) | Same as above | Low | Verify licence. |
| flutter_local_notifications | ^18.0.1 | Prayer-time / adhan notifications | BSD-3-Clause (listing) | 1 file | No | Low | — |
| timezone | ^0.10.0 | Prayer-time scheduling | BSD-2-Clause (listing) | 3 files | No | Low | — |
| geolocator | ^13.0.2 | "Optional auto-detect city" | MIT (listing) | **0 files — unused** | Location (sensitive for children); `ACCESS_COARSE_LOCATION` is declared in `android/app/src/main/AndroidManifest.additions.xml` | **High** (unused location surface) | **Removed 2026-11-22** (branch fix/child-privacy-p1): package, manifest permission and iOS usage-string note. Re-add only after docs/LOCATION_PRIVACY.md + R-31/R-27 sign-off. |
| in_app_purchase | ^3.2.0 | Subscriptions (Basic/Plus) | BSD-3-Clause (listing) | 1 file | Store billing (parent-facing) | Med | Purchase flow must stay behind the parent gate (Families policy). |
| firebase_core | ^3.8.0 | Firebase init | BSD-3-Clause (listing) | via backend.dart | Yes (Google) | Med | See §6 Firebase. |
| firebase_auth | ^5.3.3 | Anonymous auth | BSD-3-Clause (listing) | 1 file | Yes | Med | R-27 (no parent identity / VPC). |
| cloud_firestore | ^5.5.0 | Family sync (tasks, days, settings) | BSD-3-Clause (listing) | 1 file | **Yes — child activity data leaves the device** | **High** | Gated on R-27 (verifiable parental consent) and R-32/R-33 rules fixes. |
| cloud_functions | ^5.2.0 | Callables (pairing, assistant, purchases) | BSD-3-Clause (listing) | yes | Yes | Med | — |
| http | ^1.2.2 | Quran text from api.quran.com | BSD-3-Clause (listing) | 1 file | Yes (Quran Foundation) | Med | See §6. |
| crypto | ^3.0.6 | Parent PIN hashing (PBKDF2) | BSD-3-Clause (listing) | 1 file | No | Low | — |
| share_plus | ^10.1.2 | Share invite codes | BSD-3-Clause (listing) | 1 file | Opens OS share sheet | Med | Keep behind parent area (child must not share outside the app). |
| url_launcher | ^6.3.1 | Open other apps / links | BSD-3-Clause (listing) | 2 files | Opens external URLs (playstation.com, family.microsoft.com, zadx.app) | Med | Parent-gate every external link (Families "no unguarded external links"). |
| flutter_test, flutter_lints (dev) | sdk / ^5.0.0 | Tests, lints | BSD-3-Clause | dev only | No | Low | — |

## 2. Backend npm packages (`backend/functions/package.json`)

Note: the backend lives in `backend/functions/`, not `backend/`. **No `package-lock.json` exists**
(AppSec P2, R-36); CI runs `npm install` (not `npm ci`), so every run can resolve different versions.
CI does run `npm audit --audit-level=high`.

| Package | Constraint | Purpose | Licence | Risk | Action |
|---|---|---|---|---|---|
| firebase-admin | ^12.7.0 | Firestore, Messaging (server) | Apache-2.0 (listing) | Med | Lockfile. |
| firebase-functions | ^6.1.1 | Callables, scheduler, secrets | MIT (listing) | Med | Lockfile. |
| googleapis | ^144.0.0 | Play Developer API (`androidpublisher`) for purchase verification | Apache-2.0 (listing) | Med | Very large dependency tree for one API; consider `@googleapis/androidpublisher` to shrink supply-chain surface. Lockfile. |
| @types/node (dev) | ^20.17.6 | Types | MIT (listing) | Low | — |
| typescript (dev) | ^5.6.3 | Build | Apache-2.0 (listing) | Low | — |

**Action (R-36):** run `npm install` once, commit `backend/functions/package-lock.json`, switch CI to `npm ci`.

## 3. GitHub Actions (`.github/workflows/zadx-ci.yml`, `fetch-adhan.yml`)

All actions are pinned to a **major-version tag** (none to a SHA, none unpinned/`@main`). Workflow-level
`permissions: contents: read` in zadx-ci.yml (good); `publish-test-apk` and `fetch-adhan` get `contents: write`.

| Action | Version | Publisher | Licence | Secrets / write access | Risk | Action |
|---|---|---|---|---|---|---|
| actions/checkout | @v4 | GitHub | MIT (listing) | — | Low | SHA-pin optional (first-party). |
| actions/setup-java | @v4 | GitHub | MIT (listing) | — | Low | — |
| actions/setup-node | @v4 | GitHub | MIT (listing) | — | Low | — |
| actions/setup-dotnet | @v4 | GitHub | MIT (listing) | — | Low | — |
| actions/cache | @v4 | GitHub | MIT (listing) | — | Low | — |
| actions/upload-artifact / download-artifact | @v4 | GitHub | MIT (listing) | — | Low | — |
| actions/upload-pages-artifact | @v3 | GitHub | MIT (listing) | — | Low | — |
| actions/deploy-pages | @v4 | GitHub | MIT (listing) | `pages: write`, `id-token: write` | Low | — |
| dorny/paths-filter | @v3 | third-party | MIT (listing) | runs in every push/schedule job | Med | **Pin to full commit SHA** (+ `# v3.x` comment). |
| subosito/flutter-action | @v2 | third-party | MIT (listing) | builds the APK we publish | Med | **Pin to SHA** (it touches the shipped build). |
| reactivecircus/android-emulator-runner | @v2 | third-party | Apache-2.0 (listing) | — | Med | Pin to SHA. |
| google-github-actions/auth | @v2 | Google | Apache-2.0 (listing) | **receives `GCP_SA_KEY`** | Med | Pin to SHA; prefer Workload Identity Federation over a JSON key. |
| google-github-actions/setup-gcloud | @v2 | Google | Apache-2.0 (listing) | has GCP credentials in env | Med | Pin to SHA. |
| softprops/action-gh-release | @v2 | third-party | MIT (listing) | **`contents: write`**, publishes the test APK | **High** (could swap the APK owners/testers install) | **Pin to SHA first.** |

Other workflow notes:
- `fetch-adhan.yml` (manual) still downloads **5** Commons recordings incl. two **CC BY-SA 4.0** files, **overwrites** the hand-curated `assets/audio/ADHAN-CREDITS.txt`, and `git push -f` to `assets/adhans`. Only `madinah_rec` is used. **Med** — remove the workflow (registry rule: remove unused) or cut the list to `madinah_rec` and stop it overwriting the credits file. Its User-Agent embeds the owner's personal email; use a project address.
- `macos-latest` / `windows-latest` / `ubuntu-latest` runners float; acceptable for CI, not for release builds.

## 4. Native dependencies

| Area | Declared in repo | Notes | Risk | Action |
|---|---|---|---|---|
| Android Gradle | **None committed.** `android/` holds only Kotlin sources, res and `AndroidManifest.additions.xml`; Gradle files are generated in CI by `flutter create` + `android/scripts/integrate_native.py`. | Gradle deps come only from Flutter plugins (Firebase BoM etc. pulled transitively). Not auditable from the repo. | Med | Commit `pubspec.lock`; record the generated Gradle dependency tree (`./gradlew :app:dependencies`) as a CI artifact. |
| Android permissions | `AndroidManifest.additions.xml`: INTERNET, POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM, RECEIVE_BOOT_COMPLETED, ACCESS_COARSE_LOCATION, `<queries>` for game packages; accessibility service + device admin | Accessibility + device admin are high-scrutiny in Play review | Med | Drop ACCESS_COARSE_LOCATION (unused, see §1). |
| iOS CocoaPods / SPM | **None committed** (no Podfile / Package.swift / Package.resolved). Podfile generated in CI by `flutter create`; native code in `ios/Runner`, `ios/Shared`, `ios/ZadXMonitor`, `ios/ZadXShield` uses Apple frameworks (Family Controls / DeviceActivity / ManagedSettings). | Firebase iOS SDK arrives via pods from Flutter plugins. | Low–Med | Same as Android: export `Podfile.lock` from the weekly iOS job. |
| Windows Guard NuGet (`windows_guard/ZadXGuard.csproj`, net8.0-windows, self-contained) | Microsoft.Extensions.Hosting.WindowsServices **8.0.1**; Microsoft.Extensions.Http **8.0.1**; System.Security.Cryptography.ProtectedData **8.0.0** | All Microsoft, MIT (listing), exact versions pinned | Low | Add `packages.lock.json` (`RestorePackagesWithLockFile`); track .NET 8 servicing updates. `appsettings.json` still has placeholder `YOUR_FIREBASE_PROJECT` URL. |

## 5. Bundled assets

| Asset | Licence / source | Attribution duty | Risk | Action |
|---|---|---|---|---|
| `assets/audio/adhan_madinah_rec.mp3` + `android/app/src/main/res/raw/adhan_short.mp3` (28 s excerpt) | **CC BY 3.0**, ejaz215 (Freesound 33937) via Wikimedia Commons; modified (converted, trimmed, normalised) — `assets/audio/ADHAN-CREDITS.txt` | **Yes, in-app**: author, licence, link, "modified". `lib/data/catalog/quran.dart` credit = "ejaz215 · CC BY 3.0 · Freesound / Wikimedia Commons", shown in `lib/features/parent/credits_card.dart` | Med | Add licence URL + "modified" to the in-app credit. Islamic Content Reviewer to confirm the recording is a complete, correct adhan (wording not checked by tooling). `ios/Runner/adhan_short.caf` still todo. |
| Other adhan voices (Makkah, Madinah, Refaat, Alafasy) | Not licensed | — | Low (hidden: `licenceConfirmed` false / not bundled) | Keep hidden. |
| `assets/sfx/*.wav` (8 files) | Original, generated by `tools/gen_sfx.py`, © 2026 Zad X — `assets/sfx/LICENSE.txt` | None | Low | — |
| `assets/images/zadx_logo.jpg` | Owner's brand asset | None | Low | Add a one-line ownership note (no licence file today). |
| Fonts: Tajawal (5 weights), Baloo Bhaijaan 2 (variable), Amiri Quran — `assets/fonts/<family>/` | SIL OFL 1.1, unmodified from google/fonts `main` (downloaded 2026-11-23); source URL, bytes and SHA-256 per file in docs/FONTS.md | OFL text must ship with the fonts: per-family `OFL.txt` with each copyright line, shown on the Licences page (`AppFonts.configure()`) | Low | Branch `fix/bundled-fonts`, pending CI + Quality Gate. |
| Quran text (cached at runtime, not bundled) | Quran Foundation / api.quran.com | "Quran data provided by Quran Foundation" — present in credits_card | Med | See §6. Never hand-typed (ARCHITECTURE.md). |

## 6. External services / connectors

| Service | Used for | Child-side? | Licence / terms | Risk | Action |
|---|---|---|---|---|---|
| **Firebase** (project `zad-x-play`, **Spark** plan; Analytics + Gemini OFF per BACKLOG) | Auth (anonymous), Firestore family sync, Cloud Functions, FCM | **Yes** | Google Firebase ToS + DPA | **High** | (a) R-27: verifiable parental consent before child data leaves the device. (b) **Plan mismatch:** the backend deploys Cloud Functions, scheduled functions and a Secret Manager secret (`ANTHROPIC_API_KEY`) — these require the **Blaze** plan; owner decision needed, with a budget alert/cap if upgraded. (c) Keep Analytics/Crashlytics off or kid-safe configured. (d) `firebase_options.dart` not generated yet. |
| **Quran Foundation API** (approved in writing 2026-11-21) | Quran text (`api.quran.com/api/v4`) now; recitations API planned | Yes | Attribution "Quran data provided by Quran Foundation" + credit each reciter; **no rehosting** on our servers; device downloads OK; max 1-week server cache | Med | Confirm `api.quran.com/api/v4` is covered or move to the QF API with production credentials; reciter credits in-app. Adapt QF's children's privacy packet. |
| **everyayah.com** | Per-ayah Quran audio streaming (`lib/services/audio/audio_service.dart`) | **Yes** (child IP to a third party; no agreement) | **No licence on file**; QF approval does not cover it | **High — PRE-LAUNCH BLOCKER (R-34)** | Replace with QF recitations API; add a release-gate test that fails while any reciter source is everyayah. |
| **OpenStreetMap tiles via flutter_map** (planned, not in pubspec) | Child location map (`FeatureFlags.locationMap` off) | Would be | flutter_map BSD-3-Clause *(to verify)*; OSM tile usage policy: visible "© OpenStreetMap contributors", identifying User-Agent, public tiles not for heavy production use | High when built (R-31) | Do not add until LOCATION_PRIVACY.md prerequisites (R-02, R-27, R-28) are met; owner picks a production tile host with a spending cap. |
| **Anthropic API** (`askAssistant`, `backend/functions/src/index.ts`) | AI helper for parents (Plus) | **Possibly — see note** | Anthropic commercial terms; key as Functions secret `ANTHROPIC_API_KEY`; per-family daily cap + rate limit in code; `max_tokens: 500` | **High** | **Finding:** the assistant card sits on the Help screen, which opens from the main app shell (`lib/features/shell/app_shell.dart` → `Routes.help`) **with no parent-PIN gate** — only `PaidFeatureGate`. A child on a Plus family can chat with the AI. Route to AppSec / child-safety: put Help's assistant behind the parent PIN. Also set an org-level **spending limit** in the Anthropic console (owner) and confirm no child PII goes in prompts. |
| **GitHub Actions** | CI, Pages web preview, test-APK pre-release | No (but publishes what testers install) | GitHub ToS | Med | SHA-pin third-party actions (§3). Public Pages preview + public APK: label "not for children yet" is present. |
| **Firebase Test Lab** | Real-device Robo tests | No | GCP ToS | Low (inactive) | Pending `GCP_SA_KEY` secret; prefer Workload Identity Federation; key scoped to Test Lab only. |
| Google Play Developer API (`googleapis`) | Server-side purchase verification | No | Google ToS | Low | Service account least-privilege. |
| Wikimedia Commons | One-off adhan download (`fetch-adhan.yml`) | No | Per-file licence | Low | Remove workflow once audio is final (§3). |
| Google Fonts CDN | Runtime font download | **No** (google_fonts package removed 2026-11-23; fonts bundled) | Google APIs ToS | Low | Keep it out; test/bundled_fonts_test.dart guards it. |

---

## Top 5 actions (ranked: child safety & privacy first)

1. **Gate the AI assistant behind the parent PIN** (Help screen is reachable by the child from the home shell; Anthropic API then answers the child). Owner: Flutter + AppSec. Also set an Anthropic console spending limit (owner).
2. **Stop runtime calls from the child's device to third parties that have no agreement:** bundle the three OFL fonts and disable google_fonts runtime fetching; replace everyayah.com with the Quran Foundation recitations API (R-34, pre-launch blocker).
3. **Remove the unused `geolocator` package and `ACCESS_COARSE_LOCATION` permission** until the location feature clears LOCATION_PRIVACY.md / R-31 / R-27.
4. **Resolve the Firebase plan + consent question:** Cloud Functions and Secret Manager need Blaze (owner decision with budget cap); no child data to Firestore before verifiable parental consent (R-27).
5. **Supply-chain hardening (R-36):** commit `backend/functions/package-lock.json` + `npm ci`; commit `pubspec.lock`; SHA-pin `softprops/action-gh-release`, `subosito/flutter-action`, `dorny/paths-filter`, `google-github-actions/*`, `reactivecircus/android-emulator-runner`; retire or trim `fetch-adhan.yml` (it can re-add CC BY-SA files and overwrite credits).

Also: replace `intl: any`; add licence URL + "modified" to the in-app adhan credit; verify `just_audio_windows` licence; confirm every "(listing)" licence against the LICENSE files after `flutter pub get` / `npm ci`.

**Grade for this area (tooling-lead self-assessment): C** — registry now complete, no ads/analytics SDKs, but two unagreed child-side third-party calls (fonts CDN, everyayah), an ungated AI chat, an unused location package, and no lockfiles. Pending Quality Gate.
