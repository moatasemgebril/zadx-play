// Zad X Kids scheduled locks (study / bedtime / reading). Mirrors LockRulesTest.kt on Android.
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/features/schedule/scheduled_lock.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/app_lock/app_lock_service.dart';

/// 2026-11-23 is a Monday.
DateTime at(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

void main() {
  const bedtime = ScheduledLock(kind: ScheduleKind.bedtime, enabled: true, startMinute: 21 * 60, endMinute: 7 * 60);
  const study = ScheduledLock(
    kind: ScheduleKind.study,
    enabled: true,
    startMinute: 16 * 60,
    endMinute: 18 * 60,
    weekdays: schoolDays,
  );
  const reading = ScheduledLock(kind: ScheduleKind.reading, enabled: true, startMinute: 17 * 60 + 30, endMinute: 18 * 60 + 30);

  group('ScheduledLock.activeAt', () {
    test('bedtime locks at night and opens in the morning', () {
      expect(at(23, 20, 59).weekday, DateTime.monday);
      expect(bedtime.activeAt(at(23, 20, 59)), isFalse);
      expect(bedtime.activeAt(at(23, 21)), isTrue);
      expect(bedtime.activeAt(at(23, 23, 59)), isTrue);
      expect(bedtime.activeAt(at(24, 0)), isTrue);
      expect(bedtime.activeAt(at(24, 6, 59)), isTrue);
      expect(bedtime.activeAt(at(24, 7)), isFalse);
      expect(bedtime.activeAt(at(24, 12)), isFalse);
    });

    test('a night window belongs to the day it starts', () {
      final fridayOnly = bedtime.copyWith(weekdays: {DateTime.friday});
      expect(fridayOnly.activeAt(at(27, 22)), isTrue); // Friday night
      expect(fridayOnly.activeAt(at(28, 6)), isTrue); // Saturday early morning: still Friday's bedtime
      expect(fridayOnly.activeAt(at(28, 22)), isFalse); // Saturday night: not chosen
      expect(fridayOnly.activeAt(at(27, 6)), isFalse); // Friday morning = Thursday's night
    });

    test('study only on school days (Sun–Thu) and only inside the window', () {
      expect(study.activeAt(at(23, 16)), isTrue); // Monday
      expect(study.activeAt(at(23, 17, 59)), isTrue);
      expect(study.activeAt(at(23, 18)), isFalse);
      expect(study.activeAt(at(23, 15, 59)), isFalse);
      expect(study.activeAt(at(27, 16, 30)), isFalse); // Friday
      expect(study.activeAt(at(29, 16, 30)), isTrue); // Sunday
    });

    test('off, empty or zero-length windows never lock', () {
      expect(bedtime.copyWith(enabled: false).activeAt(at(23, 22)), isFalse);
      expect(bedtime.copyWith(weekdays: {}).activeAt(at(23, 22)), isFalse);
      expect(study.copyWith(endMinute: study.startMinute).activeAt(at(23, 16)), isFalse);
    });
  });

  test('bedtime wins over study, study over reading', () {
    expect(activeScheduledLock([reading, study, bedtime], at(23, 17, 45))!.kind, ScheduleKind.study);
    expect(activeScheduledLock([reading, study], at(27, 17, 45))!.kind, ScheduleKind.reading); // Friday: no study
    final late = study.copyWith(startMinute: 20 * 60, endMinute: 22 * 60);
    expect(activeScheduledLock([late, bedtime], at(23, 21, 30))!.kind, ScheduleKind.bedtime);
    expect(activeScheduledLock([reading, study, bedtime], at(23, 12)), isNull);
  });

  test('JSON round trip, junk is dropped, every kind is present once', () {
    expect(ScheduledLock.fromJson(study.toJson()), study);
    expect(ScheduledLock.fromJson({'kind': 'prayer', 'start': 1, 'end': 2}), isNull);
    expect(ScheduledLock.fromJson('x'), isNull);
    final clamped = ScheduledLock.fromJson({'kind': 'reading', 'start': -5, 'end': 99999, 'days': [0, 3, 9, 'x']})!;
    expect(clamped.startMinute, 0);
    expect(clamped.endMinute, 24 * 60 - 1);
    expect(clamped.weekdays, {3});
    final all = normaliseSchedules([study]);
    expect(all.map((s) => s.kind), ScheduleKind.values);
    expect(all.firstWhere((s) => s.kind == ScheduleKind.study), study);
  });

  group('lock policy', () {
    final wallet = WalletState(day: '2026-11-23', tasks: defaultTasks, progress: const {}, usedMinutes: 10);

    test('an active schedule locks with its kind as the reason, on every plan', () {
      final free = lockStateFor(tasksEnabled: false, wallet: wallet, dailyLimitMinutes: 60, schedule: bedtime);
      expect(free.locked, isTrue);
      expect(free.reason, 'bedtime');
      expect(free.remainingMinutes, 50);
      final paid = lockStateFor(tasksEnabled: true, wallet: wallet, dailyLimitMinutes: 60, schedule: study);
      expect(paid.locked, isTrue);
      expect(paid.reason, 'study');
    });

    test('no schedule: the existing rules are unchanged', () {
      expect(lockStateFor(tasksEnabled: false, wallet: wallet, dailyLimitMinutes: 60).locked, isFalse);
    });

    test('only enabled schedules are sent to native code', () {
      final p = lockPolicyFrom(
        locked: false,
        reason: 'none',
        remainingMinutes: 5,
        settings: const AppSettings(),
        schedules: [bedtime, study.copyWith(enabled: false), reading],
      );
      expect(p.schedules, [bedtime, reading]);
      expect(p.toMap()['schedules'], [
        {'kind': 'bedtime', 'start': 1260, 'end': 420, 'days': [1, 2, 3, 4, 5, 6, 7]},
        {'kind': 'reading', 'start': 1050, 'end': 1110, 'days': [1, 2, 3, 4, 5, 6, 7]},
      ]);
      final other = lockPolicyFrom(locked: false, reason: 'none', remainingMinutes: 5, settings: const AppSettings(), schedules: [bedtime]);
      expect(p == other, isFalse);
    });
  });
}
