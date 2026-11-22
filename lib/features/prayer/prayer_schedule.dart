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
  const AdhanSlot({required this.id, required this.prayer, required this.when});

  /// Notification id: `dayOffset * 10 + prayer.index` (stable, unique per run).
  final int id;
  final Prayer prayer;
  final tz.TZDateTime when;
}

/// The adhan notifications to schedule from [now] for [days] calendar days of the city
/// whose zone is `now.location`. Only prayers strictly after [now] are returned, in
/// strictly increasing time order.
///
/// With [HighLatitudeRule.middleOfTheNight], Isha of one day and Fajr of the next both
/// fall at the middle of the night and can round to the same minute (or Isha can be a
/// few seconds after the next Fajr). A slot that is not after the previous one is then
/// dropped, so the child never gets two adhans (or two locks) at the same moment.
List<AdhanSlot> planAdhanNotifications({
  required tz.TZDateTime now,
  required double lat,
  required double lng,
  required CalcMethod method,
  int asrFactor = 1,
  HighLatitudeRule? highLatitudeRule,
  int days = 2,
}) {
  final slots = <AdhanSlot>[];
  for (var dayOffset = 0; dayOffset < days; dayOffset++) {
    // Calendar arithmetic, not "+24 h": a DST day is 23 or 25 hours long.
    final d = DateTime.utc(now.year, now.month, now.day + dayOffset);
    final instants = prayerInstantsOn(
      location: now.location,
      year: d.year,
      month: d.month,
      day: d.day,
      lat: lat,
      lng: lng,
      method: method,
      asrFactor: asrFactor,
      highLatitudeRule: highLatitudeRule,
    );
    for (final p in Prayer.values) {
      final when = instants[p];
      if (when == null || !when.isAfter(now)) continue;
      if (slots.isNotEmpty && !when.isAfter(slots.last.when)) continue;
      slots.add(AdhanSlot(id: dayOffset * 10 + p.index, prayer: p, when: when));
    }
  }
  return slots;
}
