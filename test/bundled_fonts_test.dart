import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/core/theme/app_theme.dart';

// Regression test for the P1 privacy/offline fix: fonts used to be downloaded from Google at
// runtime on the child's device (google_fonts). They are now bundled in assets/fonts/ and
// declared under `flutter: fonts:` in pubspec.yaml; the google_fonts package is gone.
// No network access: everything here reads files from the repository.

/// The `- asset: <path>` entries of pubspec.yaml (the `fonts:` section).
List<String> _pubspecFontAssets(String pubspec) => RegExp(r'^\s*-\s*asset:\s*(\S+)\s*$', multiLine: true)
    .allMatches(pubspec)
    .map((m) => m.group(1)!)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('google_fonts is no longer a dependency', () {
    expect(pubspec, isNot(contains('google_fonts')));
  });

  test('no code imports google_fonts or points at Google font servers', () {
    final offenders = <String>[];
    for (final dir in ['lib', 'test']) {
      for (final entity in Directory(dir).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('bundled_fonts_test.dart')) continue;
        final src = entity.readAsStringSync();
        if (src.contains('package:google_fonts') ||
            src.contains('fonts.googleapis.com') ||
            src.contains('fonts.gstatic.com')) {
          offenders.add(entity.path);
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('every font asset declared in pubspec exists on disk and is a TrueType file', () {
    final assets = _pubspecFontAssets(pubspec);
    expect(assets, isNotEmpty, reason: 'pubspec.yaml has no flutter: fonts: section');
    for (final path in assets) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path is declared in pubspec.yaml but missing');
      // TrueType outlines start with 0x00010000.
      expect(file.readAsBytesSync().take(4).toList(), [0x00, 0x01, 0x00, 0x00], reason: '$path is not a TrueType font');
    }
  });

  test('pubspec fonts and AppFonts.files list the same files', () {
    expect(_pubspecFontAssets(pubspec).toSet(), AppFonts.files.toSet());
  });

  test('each family ships its own OFL licence, declared as an asset', () {
    for (final path in AppFonts.licences.values) {
      final text = File(path).readAsStringSync();
      expect(text, contains('SIL Open Font License'), reason: path);
      expect(text, contains('Copyright'), reason: path);
      expect(pubspec, contains('- $path'), reason: '$path must be listed under flutter: assets:');
    }
  });

  test('the theme uses the bundled families with the expected sizes', () {
    final theme = AppTheme.light(const Locale('ar'));
    expect(theme.textTheme.bodyMedium?.fontFamily, AppFonts.body);
    expect(theme.textTheme.titleLarge?.fontFamily, AppFonts.body);
    expect(theme.textTheme.bodyMedium?.fontSize, 16);
    expect(theme.textTheme.bodyLarge?.fontSize, 18);
    expect(theme.textTheme.titleMedium?.fontSize, 19);
    expect(theme.textTheme.titleLarge?.fontSize, 24);

    final display = AppTheme.display(26);
    expect(display.fontFamily, AppFonts.display);
    expect(display.fontSize, 26);
    expect(display.fontWeight, FontWeight.w800);

    final quran = AppTheme.quran(22);
    expect(quran.fontFamily, AppFonts.quran);
    expect(quran.height, 2.1);
  });

  test('family names in code match the families declared in pubspec', () {
    for (final family in [AppFonts.body, AppFonts.display, AppFonts.quran]) {
      expect(pubspec, contains('- family: $family'), reason: family);
    }
  });
}
