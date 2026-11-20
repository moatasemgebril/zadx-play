import 'package:flutter/foundation.dart';

/// Where Zad X is running. Game locking differs per platform:
/// * Android / iOS phones & tablets → native blockers in this app
/// * Windows PCs → the separate "Zad X Guard" service (windows_guard/)
/// * macOS, web → parent dashboard, Quran, adhkar, prayer times (no game locking yet)
class AppPlatform {
  const AppPlatform._();

  static bool get isWeb => kIsWeb;
  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Phone/tablet where this app itself locks games.
  static bool get canLockGames => isAndroid || isIOS;

  /// Store subscriptions are bought on Android, iOS and macOS (App Store).
  static bool get canPurchase => isAndroid || isIOS || isMacOS;

  /// Local (scheduled) adhan notifications.
  static bool get canScheduleNotifications => !kIsWeb;
}
