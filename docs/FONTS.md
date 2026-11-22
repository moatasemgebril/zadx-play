# Fonts — bundled only, never downloaded

Zad X Play is a children's app, so the child's device must not contact Google's font servers
(COPPA / GDPR-K: the request reveals the device IP and app use). Since 2026-11-22:

- `GoogleFonts.config.allowRuntimeFetching = false` is set by `AppFonts.configure()`
  (`lib/core/theme/app_theme.dart`), which `AppTheme.light()` calls before any text is drawn.
  `test/fonts_privacy_test.dart` fails if this is ever turned back on.
- google_fonts only uses font files found in the app's assets (`assets/fonts/`, declared in `pubspec.yaml`).

## Current state (2026-11-22)

The font files could **not** be downloaded in the build environment (the network proxy blocks
`raw.githubusercontent.com`, `fonts.google.com` and `fonts.gstatic.com`). So `AppFonts.bundled` is
`false` and the app uses the **platform fonts** (the device's default Latin and Arabic fonts) with the same sizes and
weights. Nothing is fetched.

Known effect: Quran verses and adhan phrases are shown in the platform Arabic font instead of
Amiri Quran until the files are added (listed for the Islamic Content Reviewer in
docs/localization/REVIEW-QUEUE.md).

## How to add the fonts (one commit)

1. Download each family from Google Fonts (fonts.google.com → family → "Get font" → "Download all"),
   or from the google/fonts GitHub repository (`ofl/tajawal`, `ofl/baloobhaijaan2`, `ofl/amiriquran`).
2. Copy these **static** files into `assets/fonts/` (google_fonts matches by exact file name;
   for Baloo Bhaijaan 2 use the file from the zip's `static/` folder, not the variable `[wght]` file):
   - `Tajawal-Regular.ttf`, `Tajawal-Medium.ttf`, `Tajawal-Bold.ttf`, `Tajawal-ExtraBold.ttf`
   - `BalooBhaijaan2-ExtraBold.ttf`
   - `AmiriQuran-Regular.ttf`
   (The list is `AppFonts.files`; the test checks every file exists once `bundled` is true.)
3. Open each family's `OFL.txt` and paste its copyright line(s) at the top of `assets/fonts/OFL.txt`
   (the licence text itself is already there).
4. In `lib/core/theme/app_theme.dart` set `static final bool bundled = true;`. This also registers
   `assets/fonts/OFL.txt` on the app's Licences page (`LicenseRegistry`).
5. Run `flutter test test/fonts_privacy_test.dart`; it checks that the flag and the files agree.
6. Update the google_fonts rows in docs/ADDONS-REGISTRY.md.
