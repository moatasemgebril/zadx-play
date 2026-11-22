// Zad X Kids scheduled locks (study / bedtime / reading). Mirrors LockRulesTest.kt on Android.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/features/schedule/schedule_controller.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/app_lock/app_lock_service.dart';

/// 2026-11-23 is a Monday.
DateTime at(int day, int hour, [int minute = 0]) => DateTime(2026, 11, day, hour, minute);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

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
    const wallet = WalletState(day: '2026-11-23', tasks: defaultTasks, progress: {}, usedMinutes: 10);

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

  group('clock and time zone tamper (child safety)', () {
    // 2026-11-23 20:00 UTC = Monday 22:00 in Cairo, 12:00 in Los Angeles, 15:00 in New York.
    final instant = DateTime.utc(2026, 11, 23, 20);

    test("schedules are read in the parent's saved time zone, not the phone's", () {
      final cairo = scheduleLocalTime('Africa/Cairo', instant);
      expect(cairo.hour, 22);
      expect(cairo.weekday, DateTime.monday);
      expect(bedtime.activeAt(cairo), isTrue);
      // Switching the phone to Los Angeles (noon there) does not open bedtime: the saved zone wins.
      expect(bedtime.activeAt(scheduleLocalTime('America/Los_Angeles', instant)), isFalse);
      expect(activeScheduledLock([bedtime, study], scheduleLocalTime('Africa/Cairo', instant))!.kind, ScheduleKind.bedtime);
    });

    test('unknown or missing zone falls back to the phone zone', () {
      expect(scheduleLocalTime(null, instant), instant.toLocal());
      expect(scheduleLocalTime('Mars/Olympus', instant), instant.toLocal());
    });

    test('the policy carries the parent zone to native code', () {
      final p = lockPolicyFrom(
        locked: true,
        reason: 'bedtime',
        remainingMinutes: 5,
        settings: const AppSettings(),
        schedules: [bedtime],
        scheduleTimeZone: 'America/New_York',
      );
      expect(p.toMap()['scheduleTimeZone'], 'America/New_York');
      final other = lockPolicyFrom(locked: true, reason: 'bedtime', remainingMinutes: 5, settings: const AppSettings(), schedules: [bedtime]);
      expect(p == other, isFalse);
    });

    test('a clock changed by hand is reported to the parent as tamper', () {
      final s = ProtectionStatus.fromMap({'platform': 'android', 'serviceEverEnabled': true, 'accessibility': true, 'clockChanged': true});
      expect(protectionTamperReasons(s, uninstallGuard: false), ['clock_changed']);
      final ok = ProtectionStatus.fromMap({'platform': 'android', 'serviceEverEnabled': true, 'accessibility': true});
      expect(protectionTamperReasons(ok, uninstallGuard: false), isEmpty);
    });

    test('saving a schedule records the parent zone and turns the Settings guard back on', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        deviceTimeZoneReaderProvider.overrideWithValue(() async => 'Europe/London'),
      ]);
      addTearDown(c.dispose);
      c.read(settingsProvider.notifier).setLockDeviceSettings(false);
      c.read(scheduleProvider.notifier).save(study.copyWith(enabled: true));
      expect(c.read(settingsProvider).lockDeviceSettings, isTrue, reason: 'the clock lives in Settings');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(scheduleTimeZoneProvider), 'Europe/London');
      expect(prefs.getString(ScheduleTimeZone.prefsKey), 'Europe/London');
      // Turning a schedule OFF leaves the parent's Settings choice alone.
      c.read(settingsProvider.notifier).setLockDeviceSettings(false);
      c.read(scheduleProvider.notifier).save(study.copyWith(enabled: false));
      expect(c.read(settingsProvider).lockDeviceSettings, isFalse);
    });
  });
}
