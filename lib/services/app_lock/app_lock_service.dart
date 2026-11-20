import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/platform.dart';

import '../../data/catalog/games.dart';
import '../../data/models/game.dart';
import '../../features/prayer/prayer_calculator.dart';
import '../../features/prayer/prayer_providers.dart';
import '../../features/settings/settings_controller.dart';
import '../../features/tasks/wallet_controller.dart';

enum CompanionApp {
  playStation(AppConfig.playStationFamilyAndroid, AppConfig.playStationFamilyWeb),
  microsoftFamily(AppConfig.microsoftFamilyAndroid, AppConfig.microsoftFamilyWeb);

  const CompanionApp(this.androidPackage, this.webUrl);
  final String androidPackage;
  final String webUrl;
}

/// What the native layer must enforce right now.
@immutable
class LockPolicy {
  const LockPolicy({
    required this.locked,
    required this.reason,
    required this.androidPackages,
    required this.remainingMinutes,
  });

  final bool locked;
  final String reason; // prayer | requiredTasks | noTime | none
  final List<String> androidPackages;
  final int remainingMinutes;

  Map<String, Object?> toMap() => {
        'locked': locked,
        'reason': reason,
        'androidPackages': androidPackages,
        'remainingMinutes': remainingMinutes,
      };

  @override
  bool operator ==(Object other) =>
      other is LockPolicy &&
      other.locked == locked &&
      other.reason == reason &&
      other.remainingMinutes == remainingMinutes &&
      listEquals(other.androidPackages, androidPackages);

  @override
  int get hashCode => Object.hash(locked, reason, remainingMinutes, Object.hashAll(androidPackages));
}

/// Bridge to the native blockers:
/// * Android: `AppBlockerService` (AccessibilityService) + `AppLockChannel.kt`
/// * iOS: `AppLockPlugin.swift` (FamilyControls / ManagedSettings / DeviceActivity)
class AppLockService {
  AppLockService({MethodChannel? channel, EventChannel? events})
      : _channel = channel ?? const MethodChannel('com.zadx.app/app_lock'),
        _events = events ?? const EventChannel('com.zadx.app/app_lock_events');

  final MethodChannel _channel;
  final EventChannel _events;

  /// Native events: {"type": "session_started" | "blocked_attempt" | "time_up", "package": "..."}.
  Stream<Map<String, Object?>> get events =>
      _events.receiveBroadcastStream().map((e) => Map<String, Object?>.from(e as Map));

  Future<bool> hasPermissions() async =>
      await _channel.invokeMethod<bool>('hasPermissions') ?? false;

  /// Android: opens Accessibility + Usage Access settings.
  /// iOS: requests FamilyControls authorization (.individual on child device).
  Future<bool> requestPermissions() async =>
      await _channel.invokeMethod<bool>('requestPermissions') ?? false;

  /// iOS only: shows Apple's FamilyActivityPicker so the parent selects the games.
  /// (iOS never exposes bundle ids of other apps; the selection is an opaque token.)
  Future<void> pickGamesIos() async {
    if (!AppPlatform.isIOS) return;
    await _channel.invokeMethod('pickGames');
  }

  Future<void> applyPolicy(LockPolicy policy) => _channel.invokeMethod('applyPolicy', policy.toMap());

  /// Schedules native re-locks at the given local prayer times (iOS DeviceActivity,
  /// Android AlarmManager) so locking works even if Zad X is not running.
  Future<void> schedulePrayerLocks(List<DateTime> times) => _channel.invokeMethod(
        'schedulePrayerLocks',
        {'times': times.map((t) => t.millisecondsSinceEpoch).toList()},
      );

  Future<bool> launchGame(ControlledGame game) async =>
      await _channel.invokeMethod<bool>('launchGame', {
        'androidPackage': game.androidPackage,
        'iosUrlScheme': game.iosUrlScheme,
      }) ??
      false;

  /// Opens PlayStation Family / Microsoft Family Safety. Android launches the app
  /// (or its Play Store page); iOS, web and desktop open the official web page.
  Future<void> openCompanionApp(CompanionApp app) async {
    if (AppPlatform.isAndroid) {
      await _channel.invokeMethod('openCompanionApp', {'androidPackage': app.androidPackage});
    } else {
      await launchUrl(Uri.parse(app.webUrl), mode: LaunchMode.externalApplication);
    }
  }
}

final appLockServiceProvider = Provider<AppLockService>((_) => AppLockService());

/// Derives the [LockPolicy] from the wallet + settings.
final lockPolicyProvider = Provider<LockPolicy>((ref) {
  final wallet = ref.watch(walletProvider);
  final gameIds = ref.watch(settingsProvider.select((s) => s.controlledGameIds));
  final packages = controlledGames.where((g) => gameIds.contains(g.id)).map((g) => g.androidPackage).toList()
    ..sort();
  return LockPolicy(
    locked: !wallet.gamesUnlocked,
    reason: wallet.lockReason?.name ?? 'none',
    androidPackages: packages,
    remainingMinutes: wallet.remainingMinutes,
  );
});

/// The prayer whose time most recently started (the one before "next").
Prayer _currentPrayer(Ref ref) {
  final next = ref.read(nextPrayerProvider);
  return Prayer.values[(next.index - 1 + Prayer.values.length) % Prayer.values.length];
}

/// Keep alive from the app root: pushes every policy change to native code and
/// turns native "session started" events into minute deductions.
final lockCoordinatorProvider = Provider<void>((ref) {
  if (!AppPlatform.canLockGames) return; // Windows uses Zad X Guard; web/macOS have no blocker
  final service = ref.watch(appLockServiceProvider);

  ref.listen<LockPolicy>(lockPolicyProvider, (_, policy) {
    service.applyPolicy(policy).catchError((Object e) => debugPrint('applyPolicy failed: $e'));
  }, fireImmediately: true);

  final sub = service.events.listen((event) {
    final wallet = ref.read(walletProvider.notifier);
    switch (event['type']) {
      case 'session_minute':
        // Native side reports each minute of real foreground play.
        wallet.consumeMinutes(1);
      case 'time_up':
        // iOS: the DeviceActivity budget was used up while Zad X was in the background.
        wallet.consumeMinutes(ref.read(walletProvider).remainingMinutes);
      case 'prayer_lock':
        // A native prayer alarm fired (possibly while Flutter was closed).
        if (!ref.read(walletProvider).prayerLock) wallet.startPrayerLock(_currentPrayer(ref));
    }
  }, onError: (Object e) => debugPrint('lock events error: $e'));
  ref.onDispose(sub.cancel);

  // Native alarms re-lock games at every adhan even when Zad X is closed.
  ref.listen<PrayerTimes>(prayerTimesProvider, (_, times) {
    final now = ref.read(cityNowProvider);
    final day = DateTime.utc(now.local.year, now.local.month, now.local.day);
    final instants = [
      for (final p in Prayer.values)
        if (times.of(p).isFinite)
          day.add(Duration(minutes: ((times.of(p) - now.utcOffsetHours) * 60).round())),
    ].where((t) => t.isAfter(DateTime.now().toUtc())).toList();
    if (ref.read(settingsProvider).lockAtAdhan) {
      service.schedulePrayerLocks(instants).catchError((Object e) => debugPrint('schedule failed: $e'));
    }
  }, fireImmediately: true);
});
