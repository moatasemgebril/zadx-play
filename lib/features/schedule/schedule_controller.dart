import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_variant.dart';
import '../../services/app_lock/app_lock_service.dart' show appLockServiceProvider;
import '../prayer/prayer_providers.dart' show clockProvider;
import '../settings/settings_controller.dart';
import 'scheduled_lock.dart';

export 'scheduled_lock.dart';

/// The study / bedtime / reading schedules of this device (Zad X Kids). Like the other lock
/// settings they live on the child's device and are changed in the PIN-protected parent area.
class ScheduleController extends Notifier<List<ScheduledLock>> {
  static const prefsKey = 'schedules.v1';

  @override
  List<ScheduledLock> build() {
    final raw = ref.read(sharedPrefsProvider).getString(prefsKey);
    if (raw == null) return defaultSchedules;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return defaultSchedules;
      return normaliseSchedules(list.map(ScheduledLock.fromJson).whereType<ScheduledLock>());
    } catch (e) {
      debugPrint('schedules unreadable, using defaults: $e');
      return defaultSchedules;
    }
  }

  /// Replaces the schedule of the same kind. Call only from the parent area.
  ///
  /// Also records the parent's time zone (the schedules are evaluated in it, see
  /// [scheduleTimeZoneProvider]) and, when a schedule is turned on, switches the Settings guard on:
  /// the phone's clock lives in Settings, so a schedule without it is easy to escape.
  void save(ScheduledLock schedule) {
    state = [for (final s in state) s.kind == schedule.kind ? schedule : s];
    ref.read(sharedPrefsProvider).setString(prefsKey, jsonEncode([for (final s in state) s.toJson()]));
    if (schedule.enabled && !ref.read(settingsProvider).lockDeviceSettings) {
      ref.read(settingsProvider.notifier).setLockDeviceSettings(true);
    }
    unawaited(ref.read(scheduleTimeZoneProvider.notifier).recordDeviceZone());
  }
}

final scheduleProvider = NotifierProvider<ScheduleController, List<ScheduledLock>>(ScheduleController.new);

/// Reads the phone's IANA time zone id (native `deviceTimeZone`); null when unavailable.
/// Overridden in tests.
final deviceTimeZoneReaderProvider = Provider<Future<String?> Function()>(
  (ref) => ref.read(appLockServiceProvider).deviceTimeZone,
);

/// The time zone (IANA id) the parent saved the schedules in. Bedtime / study / reading are read in
/// this zone, not in the phone's current one, so changing the phone's time zone cannot end bedtime.
/// Null until known; a fresh install records the phone's zone once ("trust on first use").
class ScheduleTimeZone extends Notifier<String?> {
  static const prefsKey = 'schedules.tz.v1';

  @override
  String? build() {
    final saved = ref.read(sharedPrefsProvider).getString(prefsKey);
    if (saved == null && kIsKids) Future.microtask(recordDeviceZone);
    return saved;
  }

  /// Stores the phone's current zone (the parent is holding the phone when this runs from [save]).
  Future<void> recordDeviceZone() async {
    try {
      final id = await ref.read(deviceTimeZoneReaderProvider)();
      if (id != null && id.isNotEmpty && id != state) set(id);
    } catch (e) {
      debugPrint('device time zone unavailable: $e');
    }
  }

  void set(String id) {
    state = id;
    ref.read(sharedPrefsProvider).setString(prefsKey, id);
  }
}

final scheduleTimeZoneProvider = NotifierProvider<ScheduleTimeZone, String?>(ScheduleTimeZone.new);

/// The schedule locking the device right now (re-checked every minute), or null.
/// Always null in Zad X Play: its locks come from prayer times instead.
final activeScheduleProvider = Provider<ScheduledLock?>((ref) {
  if (!kIsKids) return null;
  ref.watch(clockProvider);
  return activeScheduledLock(ref.watch(scheduleProvider), scheduleLocalTime(ref.watch(scheduleTimeZoneProvider)));
});
