import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/platform.dart';

import '../../data/catalog/games.dart';
import '../../data/models/game.dart';
import '../../data/models/plan.dart';
import '../../features/prayer/prayer_calculator.dart';
import '../../features/prayer/prayer_providers.dart';
import '../../features/settings/settings_controller.dart';
import '../../features/tasks/wallet_controller.dart';
import '../billing/subscription_service.dart';
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
    this.prayerAutoEndMinutes = 0,
    this.prayerLockSinceMs,
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

  /// Plans without tasks (Free): a prayer lock ends by itself this many minutes after it
  /// started. 0 = it ends only when a parent approves "I prayed" (paid plans).
  final int prayerAutoEndMinutes;

  /// When the current prayer lock started (UTC ms), only while [reason] is `prayer`. Native code uses
  /// it to recognise the same lock; the auto-end timer itself runs on elapsed time since boot.
  final int? prayerLockSinceMs;

  Map<String, Object?> toMap() => {
        'locked': locked,
        'reason': reason,
        'androidPackages': androidPackages,
        'remainingMinutes': remainingMinutes,
        'mode': mode.name,
        'allowedPackages': allowedPackages,
        'allowMessaging': allowMessaging,
        'prayerAutoEndMinutes': prayerAutoEndMinutes,
        'prayerLockSinceMs': prayerLockSinceMs,
      };

  @override
  bool operator ==(Object other) =>
      other is LockPolicy &&
      other.locked == locked &&
      other.reason == reason &&
      other.remainingMinutes == remainingMinutes &&
      other.mode == mode &&
      other.allowMessaging == allowMessaging &&
      other.prayerAutoEndMinutes == prayerAutoEndMinutes &&
      other.prayerLockSinceMs == prayerLockSinceMs &&
      listEquals(other.androidPackages, androidPackages) &&
      listEquals(other.allowedPackages, allowedPackages);

  @override
  int get hashCode => Object.hash(locked, reason, remainingMinutes, mode, allowMessaging, prayerAutoEndMinutes, prayerLockSinceMs,
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

  // ---- Device protection (docs/decisions/DEVICE-PROTECTION.md) ----
  // The window / admin calls below must only run from the parent area after [confirmParentPin].

  /// Android: Settings for the parent only + uninstall guard. iOS: Screen Time account/passcode/
  /// clock locks + `denyAppRemoval`. Safe to call repeatedly.
  Future<void> setProtection({required bool settingsLock, required bool uninstallGuard}) =>
      _channel.invokeMethod('setProtection', {'settingsLock': settingsLock, 'uninstallGuard': uninstallGuard});

  /// Android: opens the phone's Settings to the parent for [minutes] (max 10). Returns seconds left.
  Future<int> openParentWindow({int minutes = parentWindowMinutes}) async =>
      await _channel.invokeMethod<int>('openParentWindow', {'minutes': minutes}) ?? 0;

  Future<void> closeParentWindow() => _channel.invokeMethod('closeParentWindow');

  Future<int> parentWindowSeconds() async => await _channel.invokeMethod<int>('parentWindowSeconds') ?? 0;

  /// Android: one of `settings | accessibility | notifications | appDetails | usageAccess | wifi`.
  Future<bool> openDeviceSettings(String screen) async =>
      await _channel.invokeMethod<bool>('openDeviceSettings', {'screen': screen}) ?? false;

  Future<bool> deviceAdminActive() async => await _channel.invokeMethod<bool>('deviceAdminActive') ?? false;

  /// Android's own Device Admin activation screen (shows [explanation]).
  Future<void> requestDeviceAdmin(String explanation) =>
      _channel.invokeMethod('requestDeviceAdmin', {'explanation': explanation});

  Future<void> removeDeviceAdmin() => _channel.invokeMethod('removeDeviceAdmin');

  Future<ProtectionStatus> protectionStatus() async {
    if (!AppPlatform.canLockGames) return ProtectionStatus.none;
    return ProtectionStatus.fromMap(await _channel.invokeMethod<Object?>('protectionStatus'));
  }

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

/// Whether the family's plan has tasks + earned minutes (`hasFeature(tasksRewards)`: Basic,
/// Plus and the 7-day trial). Plans without tasks (Free) lock on prayer time + a parent-set
/// daily limit only, so a Free child is never locked all day.
final lockTasksEnabledProvider = Provider<bool>(
  (ref) => hasFeature(ref.watch(planEntitlementProvider), AppFeature.tasksRewards),
);

/// How long a prayer lock lasts on plans without tasks (Free), where there is no "I prayed"
/// approval: the same 20-minute window after the adhan used for the play schedule
/// ([AppConfig.playWindowAfterPrayerMinutes]).
const freePrayerLockWindow = Duration(minutes: AppConfig.playWindowAfterPrayerMinutes);

/// Lock state before it becomes a [LockPolicy] (pure, unit-tested).
typedef LockState = ({bool locked, String reason, int remainingMinutes});

/// * tasks enabled: unlocked = required tasks approved && !prayer lock && earned minutes left.
///   The prayer lock ends only when a parent approves "I prayed".
/// * tasks disabled (Free): unlocked = !prayer lock && used < [dailyLimitMinutes]. The prayer
///   lock ends by itself [freePrayerLockWindow] after it started ([now] is UTC wall time).
LockState lockStateFor({
  required bool tasksEnabled,
  required WalletState wallet,
  required int dailyLimitMinutes,
  DateTime? now,
}) {
  if (tasksEnabled) {
    return (
      locked: !wallet.gamesUnlocked,
      reason: wallet.lockReason?.name ?? 'none',
      remainingMinutes: wallet.remainingMinutes,
    );
  }
  final remaining = (dailyLimitMinutes - wallet.usedMinutes).clamp(0, 24 * 60);
  final prayerOver = wallet.prayerWindowOver(now ?? DateTime.now().toUtc(), freePrayerLockWindow);
  if (wallet.prayerLock && !prayerOver) return (locked: true, reason: 'prayer', remainingMinutes: remaining);
  if (remaining <= 0) return (locked: true, reason: 'noTime', remainingMinutes: 0);
  return (locked: false, reason: 'none', remainingMinutes: remaining);
}

/// Derives the [LockPolicy] from the wallet + settings + plan.
final lockPolicyProvider = Provider<LockPolicy>((ref) {
  ref.watch(clockProvider); // re-check every minute (Free prayer window)
  final wallet = ref.watch(walletProvider);
  final settings = ref.watch(settingsProvider);
  final tasksEnabled = ref.watch(lockTasksEnabledProvider);
  final state = lockStateFor(
    tasksEnabled: tasksEnabled,
    wallet: wallet,
    dailyLimitMinutes: settings.dailyLimitMinutes,
    now: DateTime.now().toUtc(),
  );
  return lockPolicyFrom(
    locked: state.locked,
    reason: state.reason,
    remainingMinutes: state.remainingMinutes,
    settings: settings,
    prayerAutoEndMinutes: tasksEnabled ? 0 : freePrayerLockWindow.inMinutes,
    prayerLockSinceMs: state.reason == 'prayer' ? wallet.prayerLockSince?.toUtc().millisecondsSinceEpoch : null,
  );
});

/// Pure derivation (unit-tested): settings → the policy pushed to native code.
LockPolicy lockPolicyFrom({
  required bool locked,
  required String reason,
  required int remainingMinutes,
  required AppSettings settings,
  int prayerAutoEndMinutes = 0,
  int? prayerLockSinceMs,
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
    prayerAutoEndMinutes: prayerAutoEndMinutes,
    prayerLockSinceMs: prayerLockSinceMs,
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
  // Free: end the prayer lock in the wallet once its window is over, so every screen and the
  // parent devices agree (on all platforms, also where Zad X has no native blocker).
  ref.listen<AsyncValue<DateTime>>(clockProvider, (_, __) {
    if (!ref.read(lockTasksEnabledProvider)) {
      ref.read(walletProvider.notifier).endPrayerLockIfOver(DateTime.now().toUtc(), freePrayerLockWindow);
    }
  }); // not fireImmediately: providers must not change other providers while building

  if (!AppPlatform.canLockGames) return; // Windows uses Zad X Guard; web/macOS have no blocker
  final service = ref.watch(appLockServiceProvider);

  ref.listen<LockPolicy>(lockPolicyProvider, (_, policy) {
    service.applyPolicy(policy).catchError((Object e) => debugPrint('applyPolicy failed: $e'));
  }, fireImmediately: true);

  // Device protection (Settings for the parent only, prevent deleting Zad X).
  ref.listen<({bool settingsLock, bool uninstallGuard})>(
    settingsProvider.select((s) => (settingsLock: s.lockDeviceSettings, uninstallGuard: s.preventUninstall)),
    (_, p) => service
        .setProtection(settingsLock: p.settingsLock, uninstallGuard: p.uninstallGuard)
        .catchError((Object e) => debugPrint('setProtection failed: $e')),
    fireImmediately: true,
  );

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
