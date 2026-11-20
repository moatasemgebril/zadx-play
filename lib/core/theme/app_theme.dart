import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light(Locale locale) {
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
    final textTheme = GoogleFonts.tajawalTextTheme(base.textTheme).apply(
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
  static TextStyle display(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.balooBhaijaan2(fontSize: size, fontWeight: FontWeight.w800, color: color);

  /// Mushaf-style font for Quran verses and adhan phrases.
  static TextStyle quran(double size, {Color color = AppColors.ink}) =>
      GoogleFonts.amiriQuran(fontSize: size, color: color, height: 2.1);
}
