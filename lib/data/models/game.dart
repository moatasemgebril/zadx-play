import 'package:flutter/material.dart';

import '../../core/localized.dart';

/// A third-party game Zad X can lock/unlock on the child's device.
class ControlledGame {
  const ControlledGame({
    required this.id,
    required this.name,
    required this.tag,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.androidPackage,
    this.iosUrlScheme,
    this.plusOnly = false,
    this.olderKids = false,
  });

  final String id;
  final String name;
  final Localized tag;
  final IconData icon;
  final Color bg;
  final Color fg;

  /// Used by the Android blocker and to launch the game.
  final String androidPackage;

  /// Optional deep link used to open the game on iOS (if the game supports one).
  /// On iOS, blocking itself uses the FamilyActivityPicker selection, not ids.
  final String? iosUrlScheme;

  /// Only controllable with the Plus plan.
  final bool plusOnly;

  /// Shown with an "older kids" note (battle royale / shooters).
  final bool olderKids;
}
