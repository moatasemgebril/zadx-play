import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_variant.dart';
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
  void save(ScheduledLock schedule) {
    state = [for (final s in state) s.kind == schedule.kind ? schedule : s];
    ref.read(sharedPrefsProvider).setString(prefsKey, jsonEncode([for (final s in state) s.toJson()]));
  }
}

final scheduleProvider = NotifierProvider<ScheduleController, List<ScheduledLock>>(ScheduleController.new);

/// The schedule locking the device right now (re-checked every minute), or null.
/// Always null in Zad X Play: its locks come from prayer times instead.
final activeScheduleProvider = Provider<ScheduledLock?>((ref) {
  if (!kIsKids) return null;
  ref.watch(clockProvider);
  return activeScheduledLock(ref.watch(scheduleProvider), DateTime.now());
});
