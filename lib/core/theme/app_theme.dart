import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Fonts are never downloaded on the child's device (privacy: no request to
/// Google's font servers). google_fonts only uses font files bundled in
/// `assets/fonts/`; until they are added the app uses the platform fonts with
/// the same sizes and weights. How to add them: docs/FONTS.md.
class AppFonts {
  const AppFonts._();

  /// Set to true in the same commit that adds [files] to `assets/fonts/`
  /// (test/fonts_privacy_test.dart checks the two stay in sync).
  static final bool bundled = false;

  /// The static font files google_fonts looks for (file names must match).
  static const files = [
    'Tajawal-Regular.ttf',
    'Tajawal-Medium.ttf',
    'Tajawal-Bold.ttf',
    'Tajawal-ExtraBold.ttf',
    'BalooBhaijaan2-ExtraBold.ttf',
    'AmiriQuran-Regular.ttf',
  ];

  static bool _licenceAdded = false;

  /// Turns runtime fetching off and, once the fonts ship, adds their OFL
  /// licence to the app's licences page. Safe to call more than once.
  static void configure() {
    GoogleFonts.config.allowRuntimeFetching = false;
    if (!bundled || _licenceAdded) return;
    _licenceAdded = true;
    LicenseRegistry.addLicense(() async* {
      final text = await rootBundle.loadString('assets/fonts/OFL.txt');
      yield LicenseEntryWithLineBreaks(const ['Tajawal', 'Baloo Bhaijaan 2', 'Amiri Quran'], text);
    });
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData light(Locale locale) {
    AppFonts.configure();
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.purple,
        primary: AppColors.purple,
        secondary: AppColors.yellow,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: AppColors.cream,
    );

    // Tajawal covers Arabic + Latin and stays readable for children.
    final textTheme = (AppFonts.bundled ? GoogleFonts.tajawalTextTheme(base.textTheme) : base.textTheme).apply(
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
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
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
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Display font for big playful headings.
  static TextStyle display(double size, {Color color = AppColors.ink}) => AppFonts.bundled
      ? GoogleFonts.balooBhaijaan2(fontSize: size, fontWeight: FontWeight.w800, color: color)
      : TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: color);

  /// Mushaf-style font for Quran verses and adhan phrases.
  static TextStyle quran(double size, {Color color = AppColors.ink}) => AppFonts.bundled
      ? GoogleFonts.amiriQuran(fontSize: size, color: color, height: 2.1)
      : TextStyle(fontSize: size, color: color, height: 2.1);
}
