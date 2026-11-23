import 'package:timezone/timezone.dart' as tz;

import '../../data/models/location.dart';
import 'prayer_calculator.dart';

/// The five prayers of one calendar day in a city, as exact instants.
///
/// `PrayerCalculator.compute` returns wall-clock hours for ONE fixed UTC offset. On the
/// day the clocks change (DST), the offset after the switch differs from the offset at
/// midnight, so "local midnight + hours" lands one hour off. Here the day is computed in
/// UTC and the time-zone database places each prayer, so every instant is right on any
/// day, in any zone, whatever the device's own time zone is.
///
/// A prayer is `null` when the sun never reaches its angle that day and no
/// [highLatitudeRule] is given (high latitudes in summer).
///
/// Assumption: UTC calendar day D and the city's calendar day D share the city's solar
/// noon, i.e. the city's UTC offset is within ±12 h of its longitude time. True for every
/// catalog city (guarded by a test in test/prayer_times_world_test.dart); a zone across
/// the date line from its longitude (e.g. Pacific/Kiritimati, +14) would need a day shift.
Map<Prayer, tz.TZDateTime?> prayerInstantsOn({
  required tz.Location location,
  required int year,
  required int month,
  required int day,
  required double lat,
  required double lng,
  required CalcMethod method,
  int asrFactor = 1,
  HighLatitudeRule? highLatitudeRule,
  int hijriAdjustmentDays = 0,
}) {
  final utcDay = DateTime.utc(year, month, day);
  final times = const PrayerCalculator().compute(
    date: utcDay,
    lat: lat,
    lng: lng,
    utcOffsetHours: 0,
    method: method,
    asrFactor: asrFactor,
    highLatitudeRule: highLatitudeRule,
    hijriAdjustmentDays: hijriAdjustmentDays,
  );
  return {
    for (final p in Prayer.values)
      p: times.of(p).isFinite
          ? tz.TZDateTime.from(utcDay.add(Duration(minutes: (times.of(p) * 60).round())), location)
          : null,
  };
}

/// One adhan notification to schedule.
class AdhanSlot {
  const AdhanSlot({required this.id, required this.prayer, required this.when, this.sound = true});

  /// Notification id: `dayOffset * 10 + prayer.index` (stable, unique per run).
  final int id;
  final Prayer prayer;
  final tz.TZDateTime when;

  /// False for a silent reminder (no adhan sound): see [planAdhanNotifications].
  final bool sound;
}

/// True when, with [highLatitudeRule], the Isha of [year]-[month]-[day] is at or after the next
/// day's Fajr (possible with the night-portion rules, e.g. "middle of the night" in July).
/// The parent is then shown the ECFR note on combining Maghrib and Isha.
bool ishaReachesNextFajr({
  required tz.Location location,
  required int year,
  required int month,
  required int day,
  required double lat,
  required double lng,
  required CalcMethod method,
  HighLatitudeRule? highLatitudeRule,
  int hijriAdjustmentDays = 0,
}) {
  Map<Prayer, tz.TZDateTime?> on(DateTime d) => prayerInstantsOn(
        location: location,
        year: d.year,
        month: d.month,
        day: d.day,
        lat: lat,
        lng: lng,
        method: method,
        highLatitudeRule: highLatitudeRule,
        hijriAdjustmentDays: hijriAdjustmentDays,
      );
  final isha = on(DateTime.utc(year, month, day))[Prayer.isha];
  final nextFajr = on(DateTime.utc(year, month, day + 1))[Prayer.fajr];
  return isha != null && nextFajr != null && !nextFajr.isAfter(isha);
}

/// The adhan notifications to schedule from [now] for [days] calendar days of the city
/// whose zone is `now.location`. Only prayers strictly after [now] are returned, in
/// strictly increasing time order.
///
/// With [HighLatitudeRule.middleOfTheNight], Isha of one day and Fajr of the next both
/// fall around the middle of the night; while the nights grow or shrink (e.g. July in
/// Oslo) the computed Isha can even be a few minutes AFTER the next Fajr. Isha is then NOT
/// dropped: only the adhan sound is skipped. A silent Isha reminder is planned one minute
/// after that day's Maghrib, because combining Maghrib and Isha is permitted when Isha's sign
/// is absent (ECFR resolution 3/3); the parent sees that note in Settings. So the child never
/// gets an Isha adhan after Fajr, or two adhans at the same moment.
/// Decision record: docs/decisions/PRAYER-TIMES-ACCURACY.md.
List<AdhanSlot> planAdhanNotifications({
  required tz.TZDateTime now,
  required double lat,
  required double lng,
  required CalcMethod method,
  int asrFactor = 1,
  HighLatitudeRule? highLatitudeRule,
  int days = 2,
  int hijriAdjustmentDays = 0,
}) {
  // One extra day, only to know the Fajr that follows the last Isha.
  final perDay = <Map<Prayer, tz.TZDateTime?>>[];
  for (var dayOffset = 0; dayOffset <= days; dayOffset++) {
    // Calendar arithmetic, not "+24 h": a DST day is 23 or 25 hours long.
    final d = DateTime.utc(now.year, now.month, now.day + dayOffset);
    perDay.add(prayerInstantsOn(
      location: now.location,
      year: d.year,
      month: d.month,
      day: d.day,
      lat: lat,
      lng: lng,
      method: method,
      asrFactor: asrFactor,
      highLatitudeRule: highLatitudeRule,
      hijriAdjustmentDays: hijriAdjustmentDays,
    ));
  }
  final slots = <AdhanSlot>[];
  for (var dayOffset = 0; dayOffset < days; dayOffset++) {
    final instants = perDay[dayOffset];
    for (final p in Prayer.values) {
      final when = instants[p];
      if (when == null || !when.isAfter(now)) continue;
      if (p == Prayer.isha) {
        final nextFajr = perDay[dayOffset + 1][Prayer.fajr];
        final maghrib = instants[Prayer.maghrib];
        if (nextFajr != null && !nextFajr.isAfter(when)) {
          // Silent Isha with Maghrib (see above), never dropped.
          final silentAt = maghrib?.add(const Duration(minutes: 1));
          if (silentAt != null && silentAt.isAfter(now) && (slots.isEmpty || silentAt.isAfter(slots.last.when))) {
            slots.add(AdhanSlot(id: dayOffset * 10 + p.index, prayer: p, when: silentAt, sound: false));
          }
          continue;
        }
      }
      if (slots.isNotEmpty && !when.isAfter(slots.last.when)) continue;
      slots.add(AdhanSlot(id: dayOffset * 10 + p.index, prayer: p, when: when));
    }
  }
  return slots;
}
