# Fonts — bundled only, never downloaded

Zad X Play is a children's app, so the child's device must not contact Google's font servers
(COPPA / GDPR-K: the request reveals the device IP and app use) and the app must work offline.

## Current state (2026-11-23, branch `fix/bundled-fonts`)

- The font files are **bundled** in `assets/fonts/<family>/` and declared under `flutter: fonts:` in
  `pubspec.yaml`. The theme uses plain `fontFamily:` text styles (`lib/core/theme/app_theme.dart`,
  `AppFonts` / `AppTheme`).
- The **`google_fonts` package was removed** from `pubspec.yaml`, so no code path can fetch a font at runtime.
- Each family's own `OFL.txt` (with its copyright line) ships next to its files and is listed on the
  app's Licences page (`AppFonts.configure()` → `LicenseRegistry`).
- `test/bundled_fonts_test.dart` (no network) fails if google_fonts comes back, if a declared font file
  is missing or not a TrueType file, if `AppFonts.files` and pubspec disagree, or if a licence file is missing.

Weights bundled: the app uses `FontWeight.w600`–`w900` plus the Material defaults (400/500), so Tajawal ships
400, 500, 700, 800, 900 (w600 resolves to 700). Baloo Bhaijaan 2 is only published upstream as a variable
font; it is bundled unmodified, declared as weight 800, and `AppTheme.display` sets `FontVariation('wght', 800)`.
Amiri Quran has a single Regular style.

## Font file registry

All files were downloaded on 2026-11-23 from the official google/fonts repository, branch `main`
(`https://raw.githubusercontent.com/google/fonts/main/ofl/<family>/<file>`), unmodified.
Licence for all: **SIL Open Font License 1.1** (OFL-1.1). Attribution duty: ship the OFL text with the
fonts (done: per-family `OFL.txt`, also shown on the Licences page). Fonts may not be sold by themselves.

| Bundled file | Upstream file (`ofl/…`) | Bytes | SHA-256 |
|---|---|---|---|
| `assets/fonts/tajawal/Tajawal-Regular.ttf` | `tajawal/Tajawal-Regular.ttf` | 60364 | `6882892da3e03527d5db2bbab3b48bde6ef2e878a43f522d1a4eebda90010a19` |
| `assets/fonts/tajawal/Tajawal-Medium.ttf` | `tajawal/Tajawal-Medium.ttf` | 62280 | `1ff8bd943a261c9dd7906bdb1993cab87b6d925a7fb5f848cdb51ed301531090` |
| `assets/fonts/tajawal/Tajawal-Bold.ttf` | `tajawal/Tajawal-Bold.ttf` | 59988 | `0342ab6b74b6bd1b4b5bf7beda45a9734a2b3147a31e8a3a45b6a3417a52d9d7` |
| `assets/fonts/tajawal/Tajawal-ExtraBold.ttf` | `tajawal/Tajawal-ExtraBold.ttf` | 59648 | `3d1298b747c22579f9e1bdeb0d4165064cb17f7e66145e2f43f9deb12ad7a2cf` |
| `assets/fonts/tajawal/Tajawal-Black.ttf` | `tajawal/Tajawal-Black.ttf` | 59028 | `da582a579d3200869535dc994d2349608a8582042f8776b3679b157015db287c` |
| `assets/fonts/tajawal/OFL.txt` | `tajawal/OFL.txt` | 4464 | `9b584984f9db0ee30347391a76eff9c0a6b03dc450c3c6afe3757a2cb3a4db87` |
| `assets/fonts/baloobhaijaan2/BalooBhaijaan2-VariableFont_wght.ttf` | `baloobhaijaan2/BalooBhaijaan2[wght].ttf` (renamed only: no brackets in asset paths) | 285508 | `3e9f07fbc796c0ddcb3e6e0aa26f9c86741d9f5b7f5cb72f4ed3c06e55a19336` |
| `assets/fonts/baloobhaijaan2/OFL.txt` | `baloobhaijaan2/OFL.txt` | 4384 | `ad09b05dc8bc678c9daf7c4c5f7ef1f55e5726127f4330b2e98e40b9dffcb860` |
| `assets/fonts/amiriquran/AmiriQuran-Regular.ttf` | `amiriquran/AmiriQuran-Regular.ttf` | 136920 | `e2a47644762d16bdfb6d33e0d8db8c6ff30beae84150ef5a705316bbd829455c` |
| `assets/fonts/amiriquran/OFL.txt` | `amiriquran/OFL.txt` | 4392 | `b32e3b24e2a943b8acbf6ab8d5499bfed737d5176091b7341a8c1e7fbcdeb0fa` |

Copyright lines (copied from each upstream `OFL.txt`, not typed from memory):

- Tajawal: "Copyright 2018 Boutros International. (http://www.boutrosfonts.com)"
- Baloo Bhaijaan 2: "Copyright 2019 The Baloo 2 Project Authors (https://github.com/EkType/Baloo2)"
- Amiri Quran: "Copyright 2010-2022 The Amiri Quran Project Authors (https://github.com/aliftype/amiri)."

Total font payload (TTF files): 723,736 bytes (about 0.72 MB).

To verify: `sha256sum assets/fonts/*/*`.

## Adding or changing a font

1. Download from the google/fonts repository (`ofl/<family>/`), unmodified, plus that family's `OFL.txt`.
2. Put the files in `assets/fonts/<family>/`, declare them under `flutter: fonts:` in `pubspec.yaml`,
   add the paths to `AppFonts.files` and the licence to `AppFonts.licences` + `flutter: assets:`.
3. Add a row (source, bytes, SHA-256) to the registry above.
4. Run `flutter test test/bundled_fonts_test.dart`.
5. Never re-add `google_fonts` or any runtime font download.
