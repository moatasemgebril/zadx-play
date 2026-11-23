import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';

/// Fonts ship inside the app (`assets/fonts/`, declared under `flutter: fonts:` in
/// pubspec.yaml). Nothing is ever downloaded on the child's device (privacy: no request to
/// Google's font servers; works offline). Sources, licences and SHA-256: docs/FONTS.md.
class AppFonts {
  const AppFonts._();

  /// Body/UI family (Arabic + Latin, readable for children). Weights 400/500/700/800/900.
  static const body = 'Tajawal';

  /// Playful display family. Bundled as the upstream variable font (wght 400–800).
  static const display = 'Baloo Bhaijaan 2';

  /// Mushaf-style family for Quran verses and adhan phrases.
  static const quran = 'Amiri Quran';

  /// Every bundled font file. Must match the `fonts:` section of pubspec.yaml
  /// (test/bundled_fonts_test.dart checks the files exist and are declared).
  static const files = [
    'assets/fonts/tajawal/Tajawal-Regular.ttf',
    'assets/fonts/tajawal/Tajawal-Medium.ttf',
    'assets/fonts/tajawal/Tajawal-Bold.ttf',
    'assets/fonts/tajawal/Tajawal-ExtraBold.ttf',
    'assets/fonts/tajawal/Tajawal-Black.ttf',
    'assets/fonts/baloobhaijaan2/BalooBhaijaan2-VariableFont_wght.ttf',
    'assets/fonts/amiriquran/AmiriQuran-Regular.ttf',
  ];

  /// Per-family OFL licence files (with each family's own copyright line), shown on the
  /// app's Licences page.
  static const licences = {
    'Tajawal': 'assets/fonts/tajawal/OFL.txt',
    'Baloo Bhaijaan 2': 'assets/fonts/baloobhaijaan2/OFL.txt',
    'Amiri Quran': 'assets/fonts/amiriquran/OFL.txt',
  };

  static bool _licenceAdded = false;

  /// Adds the fonts' OFL licences to the app's Licences page. Safe to call more than once.
  static void configure() {
    if (_licenceAdded) return;
    _licenceAdded = true;
    LicenseRegistry.addLicense(() async* {
      for (final entry in licences.entries) {
        final text = await rootBundle.loadString(entry.value);
        yield LicenseEntryWithLineBreaks([entry.key], text);
      }
    });
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData light(Locale locale) {
    AppFonts.configure();
    final base = ThemeData(
      useMaterial3: true,
      // Tajawal covers Arabic + Latin and stays readable for children.
      fontFamily: AppFonts.body,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.purple,
        primary: AppColors.purple,
        secondary: AppColors.yellow,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.cream,
    );

    final textTheme = base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    return base.copyWith(
      textTheme: textTheme.copyWith(
        bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: 16),
        bodyLarge: textTheme.bodyLarge?.copyWith(fontSize: 18),
        titleMedium: textTheme.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w800),
        titleLarge: textTheme.titleLarge?.copyWith(fontSize: 24, fontWeight: FontWeight.w800),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontFamily: AppFonts.body, fontSize: 17, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.purpleSoft,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: AppFonts.body, fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Display font for big playful headings. The file is a variable font, so the weight is
  /// also set on its `wght` axis (pubspec declares the file as weight 800 to avoid faux bold).
  static TextStyle display(double size, {Color color = AppColors.ink}) => TextStyle(
        fontFamily: AppFonts.display,
        fontSize: size,
        fontWeight: FontWeight.w800,
        fontVariations: const [FontVariation('wght', 800)],
        color: color,
      );

  /// Mushaf-style font for Quran verses and adhan phrases.
  static TextStyle quran(double size, {Color color = AppColors.ink}) =>
      TextStyle(fontFamily: AppFonts.quran, fontSize: size, color: color, height: 2.1);
}
