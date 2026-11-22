import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/app_variant.dart';

/// Neutral scheduled locks of Zad X Kids (they replace the prayer lock of Zad X Play).
/// Decision record: docs/decisions/ZADX-KIDS-VARIANT.md.
///
/// The same rule runs natively on Android (`LockRules.activeSchedule` in LockRules.kt) so the
/// device locks on time even when Zad X is closed. Keep both in sync.
enum ScheduleKind {
  /// Night lock + morning unlock (crosses midnight).
  bedtime,

  /// Homework / study slot, usually on school days.
  study,

  /// A daily reading slot (a book or a story, away from the screen).
  reading;

  static ScheduleKind? parse(Object? value) {
    for (final k in values) {
      if (k.name == value) return k;
    }
    return null;
  }
}

const Set<int> everyDay = {
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
  DateTime.saturday,
  DateTime.sunday,
};

/// Sunday–Thursday: the school week in Egypt and most Arab countries (Zad X Play).
const Set<int> schoolDays = {
  DateTime.sunday,
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
};

/// Monday–Friday: the school week in the US and Europe (Zad X Kids, Western market).
const Set<int> westernSchoolDays = {
  DateTime.monday,
  DateTime.tuesday,
  DateTime.wednesday,
  DateTime.thursday,
  DateTime.friday,
};

/// Default study days of each app (the parent can change them).
Set<int> schoolDaysFor(AppVariant variant) => variant == AppVariant.kids ? westernSchoolDays : schoolDays;

/// Local time used to evaluate the schedules: [utcNow] read in the time zone the parent saved the
/// schedules in ([parentTimeZone], an IANA id). Changing the phone's time zone therefore cannot move
/// bedtime. Falls back to the phone's own zone when no (valid) id is known.
DateTime scheduleLocalTime(String? parentTimeZone, [DateTime? utcNow]) {
  final now = utcNow ?? DateTime.now();
  if (parentTimeZone != null && parentTimeZone.isNotEmpty) {
    try {
      return tz.TZDateTime.from(now, tz.getLocation(parentTimeZone));
    } catch (_) {
      // Unknown id or time zone data not loaded: use the phone's zone.
    }
  }
  return now.toLocal();
}

/// One lock window in local device time. [startMinute]/[endMinute] are minutes after midnight;
/// when `endMinute <= startMinute` the window crosses midnight (bedtime 21:00 → 07:00).
/// [weekdays] (DateTime.monday..DateTime.sunday) are the days on which the window STARTS.
@immutable
class ScheduledLock {
  const ScheduledLock({
    required this.kind,
    required this.startMinute,
    required this.endMinute,
    this.enabled = false,
    this.weekdays = everyDay,
  });

  final ScheduleKind kind;
  final bool enabled;
  final int startMinute;
  final int endMinute;
  final Set<int> weekdays;

  bool get crossesMidnight => endMinute < startMinute;

  /// Length in minutes (0 when start == end: such a window never locks).
  int get durationMinutes => crossesMidnight ? 24 * 60 - startMinute + endMinute : endMinute - startMinute;

  /// True when this window locks the device at local time [local].
  bool activeAt(DateTime local) {
    if (!enabled || durationMinutes <= 0 || weekdays.isEmpty) return false;
    final m = local.hour * 60 + local.minute;
    final today = local.weekday;
    final yesterday = today == DateTime.monday ? DateTime.sunday : today - 1;
    if (!crossesMidnight) return weekdays.contains(today) && m >= startMinute && m < endMinute;
    return (weekdays.contains(today) && m >= startMinute) || (weekdays.contains(yesterday) && m < endMinute);
  }

  ScheduledLock copyWith({bool? enabled, int? startMinute, int? endMinute, Set<int>? weekdays}) => ScheduledLock(
        kind: kind,
        enabled: enabled ?? this.enabled,
        startMinute: clampMinute(startMinute ?? this.startMinute),
        endMinute: clampMinute(endMinute ?? this.endMinute),
        weekdays: weekdays ?? this.weekdays,
      );

  static int clampMinute(int m) => m.clamp(0, 24 * 60 - 1);

  Map<String, Object> toJson() => {
        'kind': kind.name,
        'enabled': enabled,
        'start': startMinute,
        'end': endMinute,
        'days': weekdays.toList()..sort(),
      };

  /// Null when [json] is not a valid schedule.
  static ScheduledLock? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = ScheduleKind.parse(json['kind']);
    final start = json['start'];
    final end = json['end'];
    if (kind == null || start is! int || end is! int) return null;
    final days = <int>{
      for (final d in (json['days'] is List ? json['days'] as List : const []))
        if (d is int && d >= DateTime.monday && d <= DateTime.sunday) d,
    };
    return ScheduledLock(
      kind: kind,
      enabled: json['enabled'] == true,
      startMinute: clampMinute(start),
      endMinute: clampMinute(end),
      weekdays: days,
    );
  }

  /// What the native blockers get (only enabled windows are sent).
  Map<String, Object> toNative() => {
        'kind': kind.name,
        'start': startMinute,
        'end': endMinute,
        'days': weekdays.toList()..sort(),
      };

  @override
  bool operator ==(Object other) =>
      other is ScheduledLock &&
      other.kind == kind &&
      other.enabled == enabled &&
      other.startMinute == startMinute &&
      other.endMinute == endMinute &&
      setEquals(other.weekdays, weekdays);

  @override
  int get hashCode => Object.hash(kind, enabled, startMinute, endMinute, Object.hashAllUnordered(weekdays));
}

/// Starter schedules: bedtime on (21:00 → 07:00 every night), study (16:00–18:00 on school days:
/// Mon–Fri in Zad X Kids, Sun–Thu in Zad X Play) and reading (19:00–19:30 daily) off until the
/// parent turns them on.
List<ScheduledLock> defaultSchedulesFor(AppVariant variant) => [
      const ScheduledLock(kind: ScheduleKind.bedtime, enabled: true, startMinute: 21 * 60, endMinute: 7 * 60),
      ScheduledLock(kind: ScheduleKind.study, startMinute: 16 * 60, endMinute: 18 * 60, weekdays: schoolDaysFor(variant)),
      const ScheduledLock(kind: ScheduleKind.reading, startMinute: 19 * 60, endMinute: 19 * 60 + 30),
    ];

/// The starter schedules of this build.
final List<ScheduledLock> defaultSchedules = List.unmodifiable(defaultSchedulesFor(appVariant));

// CLDR week data (supplemental weekData "firstDay"): regions whose week starts on Sunday / Saturday.
const _sundayFirst = {
  'AG', 'AS', 'BD', 'BR', 'BS', 'BT', 'BW', 'BZ', 'CA', 'CN', 'CO', 'DM', 'DO', 'ET', 'GT', 'GU', 'HK', 'HN', //
  'ID', 'IL', 'IN', 'JM', 'JP', 'KE', 'KH', 'KR', 'LA', 'MH', 'MM', 'MO', 'MT', 'MX', 'MZ', 'NI', 'NP', 'PA', //
  'PE', 'PH', 'PK', 'PR', 'PT', 'PY', 'SA', 'SG', 'SV', 'TH', 'TT', 'TW', 'UM', 'US', 'VE', 'VI', 'WS', 'YE', //
  'ZA', 'ZW',
};
const _saturdayFirst = {'AE', 'AF', 'BH', 'DJ', 'DZ', 'EG', 'IQ', 'IR', 'JO', 'KW', 'LY', 'OM', 'QA', 'SD', 'SY'};

/// ISO weekday (DateTime.monday..sunday) the week starts on for the phone's locale: Sunday in the
/// US, Monday in most of Europe, Saturday in Egypt. Without a region: English → Sunday (US),
/// Arabic → Saturday, anything else → Monday.
int firstWeekdayFor(String languageCode, [String? countryCode]) {
  final region = countryCode?.toUpperCase();
  if (region != null && region.isNotEmpty) {
    if (_sundayFirst.contains(region)) return DateTime.sunday;
    if (_saturdayFirst.contains(region)) return DateTime.saturday;
    if (region == 'MV') return DateTime.friday;
    return DateTime.monday;
  }
  return switch (languageCode) { 'en' => DateTime.sunday, 'ar' => DateTime.saturday, _ => DateTime.monday };
}

/// The seven ISO weekdays starting at [first].
List<int> weekdayOrder(int first) => [for (var i = 0; i < 7; i++) (first - 1 + i) % 7 + 1];

/// The window locking the device at [local], or null. Bedtime wins over study, study over reading.
ScheduledLock? activeScheduledLock(Iterable<ScheduledLock> schedules, DateTime local) {
  ScheduledLock? best;
  for (final s in schedules) {
    if (!s.activeAt(local)) continue;
    if (best == null || s.kind.index < best.kind.index) best = s;
  }
  return best;
}

/// Exactly one schedule per kind, in [ScheduleKind] order; missing kinds get their default.
List<ScheduledLock> normaliseSchedules(Iterable<ScheduledLock> saved) => [
      for (final kind in ScheduleKind.values)
        saved.where((s) => s.kind == kind).firstOrNull ?? defaultSchedules.firstWhere((d) => d.kind == kind),
    ];
