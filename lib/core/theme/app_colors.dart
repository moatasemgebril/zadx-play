import 'package:flutter/material.dart';

/// Zad X palette. Text colours meet WCAG AA on the backgrounds they are used on.
class AppColors {
  const AppColors._();

  static const navy = Color(0xFF0A225E); // header, matches logo
  static const purple = Color(0xFF6C3BEB); // primary actions
  static const purpleDark = Color(0xFF4C1DB8);
  static const purpleSoft = Color(0xFFF1E9FF);
  static const yellow = Color(0xFFFFC83D);
  static const coral = Color(0xFFFF6B6B);
  static const sky = Color(0xFF4CC9F0);
  static const mint = Color(0xFF2DBE7E);
  static const mintSoft = Color(0xFFDDF7F0);
  static const mintText = Color(0xFF065F55);
  static const cream = Color(0xFFFFF8F0);
  static const ink = Color(0xFF1F1A3D);
  static const muted = Color(0xFF5E5A78);
  static const lockBg = Color(0xFFFFE4E1);
  static const lockText = Color(0xFF9B1C2E);
  static const pendingBg = Color(0xFFFFF3C4);
  static const pendingText = Color(0xFF6B4E00);
  static const psBlue = Color(0xFF1D4ED8);

  /// Background tint per main section.
  static const pageTints = {
    'home': Color(0xFFFFF8F0),
    'games': Color(0xFFF4EEFF),
    'quran': Color(0xFFFFF9E6),
    'tasks': Color(0xFFEDFAF4),
    'parent': Color(0xFFEEF4FF),
  };
}
