import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:zadx/core/theme/app_theme.dart';

// Regression test for P1 privacy: google_fonts downloaded fonts from Google at
// runtime on the child's device. Fonts must be bundled; fetching stays off.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('runtime font fetching is turned off', () {
    GoogleFonts.config.allowRuntimeFetching = true;
    AppFonts.configure();
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
  });

  test('building the app theme turns runtime fetching off', () {
    GoogleFonts.config.allowRuntimeFetching = true;
    final theme = AppTheme.light(const Locale('ar'));
    expect(GoogleFonts.config.allowRuntimeFetching, isFalse);
    // Same sizes whether the fonts are bundled or the platform fonts are used.
    expect(theme.textTheme.bodyMedium?.fontSize, 16);
    expect(theme.textTheme.bodyLarge?.fontSize, 18);
    expect(theme.textTheme.titleMedium?.fontSize, 19);
    expect(theme.textTheme.titleLarge?.fontSize, 24);
    expect(AppTheme.display(26).fontSize, 26);
    expect(AppTheme.quran(22).height, 2.1);
  });

  test('the bundled flag matches the font files in assets/fonts', () {
    final present = AppFonts.files.where((f) => File('assets/fonts/$f').existsSync()).toList();
    if (AppFonts.bundled) {
      expect(present, AppFonts.files, reason: 'AppFonts.bundled is true but font files are missing (docs/FONTS.md)');
    } else {
      expect(present, isEmpty, reason: 'Font files were added: set AppFonts.bundled = true (docs/FONTS.md)');
    }
  });

  test('the OFL licence ships with the fonts and the folder is an asset', () {
    expect(File('assets/fonts/OFL.txt').readAsStringSync(), contains('SIL OPEN FONT LICENSE Version 1.1'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/fonts/'));
  });
}
