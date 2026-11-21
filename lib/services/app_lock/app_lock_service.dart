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
import 'lock_rules.dart';

export 'lock_rules.dart';

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
    this.mode = LockMode.allApps,
    this.allowedPackages = const [],
    this.allowMessaging = true,
  });

  final bool locked;
  final String reason; // prayer | requiredTasks | noTime | none

  /// Games the parent selected (the lock list in [LockMode.selectedGames]).
  final List<String> androidPackages;
  final int remainingMinutes;

  /// [LockMode.allApps]: everything except the always-allowed core and [allowedPackages] is locked,
  /// and earned minutes are spent on any non-allowed app.
  final LockMode mode;

  /// Android packages the parent always allows (sorted). iOS uses an opaque picker selection instead.
  final List<String> allowedPackages;

  /// SMS + contacts apps stay open (contact with parents). Phone and emergency are always open.
  final bool allowMessaging;

  Map<String, Object?> toMap() => {
        'locked': locked,
        'reason': reason,
        'androidPackages': androidPackages,
        'remainingMinutes': remainingMinutes,
        'mode': mode.name,
        'allowedPackages': allowedPackages,
        'allowMessaging': allowMessaging,
      };

  @override
  bool operator ==(Object other) =>
      other is LockPolicy &&
      other.locked == locked &&
      other.reason == reason &&
      other.remainingMinutes == remainingMinutes &&
      other.mode == mode &&
      other.allowMessaging == allowMessaging &&
      listEquals(other.androidPackages, androidPackages) &&
      listEquals(other.allowedPackages, allowedPackages);

  @override
  int get hashCode => Object.hash(locked, reason, remainingMinutes, mode, allowMessaging,
      Object.hashAll(androidPackages), Object.hashAll(allowedPackages));
}

/// An installed app shown in the parent's allow-list editor (Android only; never uploaded).
@immutable
class InstalledApp {
  const InstalledApp(this.package, this.label);
  final String package;
  final String label;

  static List<InstalledApp> listFrom(Object? raw) => [
        for (final e in (raw as List?) ?? const [])
          if (e is Map && e['package'] is String)
            InstalledApp(e['package'] as String, (e['label'] as String?) ?? e['package'] as String),
      ];
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

  /// iOS only: Apple's picker for the apps/websites that stay open in [LockMode.allApps].
  Future<void> pickAllowedAppsIos() async {
    if (!AppPlatform.isIOS) return;
    await _channel.invokeMethod('pickAllowedApps');
  }

  /// Android only: launchable apps the parent can add to the allow-list.
  Future<List<InstalledApp>> listApps() async {
    if (!AppPlatform.isAndroid) return const [];
    return InstalledApp.listFrom(await _channel.invokeMethod<List<Object?>>('listApps'));
  }

  /// Android only: installed apps that are never locked on this device (phone, launcher, keyboard…).
  Future<List<InstalledApp>> alwaysAllowedApps({required bool allowMessaging}) async {
    if (!AppPlatform.isAndroid) return const [];
    return InstalledApp.listFrom(
      await _channel.invokeMethod<List<Object?>>('alwaysAllowedApps', {'allowMessaging': allowMessaging}),
    );
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

/// Whether the family's plan has tasks + earned minutes. Plans without tasks (Free) lock on
/// prayer time + a parent-set daily limit only, so a Free child is never locked all day.
/// TODO(plans PR #22): override/wire this to the entitlement (do not import plan.dart here).
final lockTasksEnabledProvider = Provider<bool>((_) => true);

/// Lock state before it becomes a [LockPolicy] (pure, unit-tested).
typedef LockState = ({bool locked, String reason, int remainingMinutes});

/// * tasks enabled: unlocked = required tasks approved && !prayer lock && earned minutes left
/// * tasks disabled (Free): unlocked = !prayer lock && used < [dailyLimitMinutes]
LockState lockStateFor({required bool tasksEnabled, required WalletState wallet, required int dailyLimitMinutes}) {
  if (tasksEnabled) {
    return (
      locked: !wallet.gamesUnlocked,
      reason: wallet.lockReason?.name ?? 'none',
      remainingMinutes: wallet.remainingMinutes,
    );
  }
  final remaining = (dailyLimitMinutes - wallet.usedMinutes).clamp(0, 24 * 60);
  if (wallet.prayerLock) return (locked: true, reason: 'prayer', remainingMinutes: remaining);
  if (remaining <= 0) return (locked: true, reason: 'noTime', remainingMinutes: 0);
  return (locked: false, reason: 'none', remainingMinutes: remaining);
}

/// Derives the [LockPolicy] from the wallet + settings.
final lockPolicyProvider = Provider<LockPolicy>((ref) {
  final wallet = ref.watch(walletProvider);
  final settings = ref.watch(settingsProvider);
  final state = lockStateFor(
    tasksEnabled: ref.watch(lockTasksEnabledProvider),
    wallet: wallet,
    dailyLimitMinutes: settings.dailyLimitMinutes,
  );
  return lockPolicyFrom(
    locked: state.locked,
    reason: state.reason,
    remainingMinutes: state.remainingMinutes,
    settings: settings,
  );
});

/// Pure derivation (unit-tested): settings → the policy pushed to native code.
LockPolicy lockPolicyFrom({
  required bool locked,
  required String reason,
  required int remainingMinutes,
  required AppSettings settings,
}) {
  final packages = controlledGames
      .where((g) => settings.controlledGameIds.contains(g.id))
      .map((g) => g.androidPackage)
      .toList()
    ..sort();
  return LockPolicy(
    locked: locked,
    reason: reason,
    androidPackages: packages,
    remainingMinutes: remainingMinutes,
    mode: settings.lockMode,
    allowedPackages: settings.allowedApps.toList()..sort(),
    allowMessaging: settings.allowMessaging,
  );
}

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
        if (ref.read(lockTasksEnabledProvider)) {
          wallet.consumeMinutes(1);
        } else {
          wallet.addUsedMinutes(1, cap: ref.read(settingsProvider).dailyLimitMinutes);
        }
      case 'time_up':
        // iOS: the DeviceActivity budget was used up while Zad X was in the background.
        if (ref.read(lockTasksEnabledProvider)) {
          wallet.consumeMinutes(ref.read(walletProvider).remainingMinutes);
        } else {
          final cap = ref.read(settingsProvider).dailyLimitMinutes;
          wallet.addUsedMinutes(cap, cap: cap);
        }
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
