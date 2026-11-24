// Prayer times when the clock changes: DST in the US, EU, Australia and Egypt, places
// without DST, the year boundary, the leap day, a traveller whose phone is in another
// time zone, and the adhan notification plan around midnight and DST switches.
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:zadx/data/catalog/locations.dart';
import 'package:zadx/features/prayer/city_time_zone.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_schedule.dart';

import 'support/prayer_cases.dart';
import 'support/solar_reference.dart';

Duration _offsetAtNoon(tz.Location loc, DateTime d) => tz.TZDateTime(loc, d.year, d.month, d.day, 12).timeZoneOffset;

Map<Prayer, tz.TZDateTime?> _instants(WorldCase c, DateTime d) => prayerInstantsOn(
      location: tz.getLocation(c.city.timeZone),
      year: d.year,
      month: d.month,
      day: d.day,
      lat: c.city.lat,
      lng: c.city.lng,
      method: c.method,
      asrFactor: c.asrFactor,
    );

/// Reference instant (UTC) of [p] for city [c] on [d].
DateTime? _refInstant(WorldCase c, DateTime d, Prayer p) {
  final r = referenceFor(c, d);
  final minutes = switch (p) {
    Prayer.fajr => r.fajr,
    Prayer.dhuhr => r.transit + 1,
    Prayer.asr => r.asr,
    Prayer.maghrib => r.maghrib,
    Prayer.isha => r.isha,
  };
  return minutes == null ? null : DateTime.utc(d.year, d.month, d.day).add(Duration(seconds: (minutes * 60).round()));
}

double _minutesApart(DateTime a, DateTime b) => a.difference(b).inSeconds.abs() / 60;

double _wallHours(tz.TZDateTime t) => t.hour + t.minute / 60 + t.second / 3600;

/// Days in [from, to) whose noon UTC offset differs from the previous day's.
List<DateTime> _transitionDays(tz.Location loc, DateTime from, DateTime to) {
  final days = <DateTime>[];
  var prev = _offsetAtNoon(loc, from);
  for (var d = DateTime.utc(from.year, from.month, from.day + 1); d.isBefore(to); d = DateTime.utc(d.year, d.month, d.day + 1)) {
    final off = _offsetAtNoon(loc, d);
    if (off != prev) days.add(d);
    prev = off;
  }
  return days;
}

void main() {
  tzdata.initializeTimeZones(); // before the groups: some test lists are built from the database

  group('time-zone database used by the app', () {
    void expectOffset(String zone, DateTime d, double hours) {
      expect(
        _offsetAtNoon(tz.getLocation(zone), d).inMinutes / 60,
        hours,
        reason: '$zone on ${d.toIso8601String().substring(0, 10)}',
      );
    }

    test('US/Canada: DST from the 2nd Sunday of March to the 1st Sunday of November', () {
      for (final zone in ['America/New_York', 'America/Toronto']) {
        expectOffset(zone, DateTime(2026, 3, 7), -5);
        expectOffset(zone, DateTime(2026, 3, 8), -4);
        expectOffset(zone, DateTime(2026, 10, 31), -4);
        expectOffset(zone, DateTime(2026, 11, 1), -5);
        expectOffset(zone, DateTime(2027, 3, 13), -5);
        expectOffset(zone, DateTime(2027, 3, 14), -4);
        expectOffset(zone, DateTime(2027, 11, 6), -4);
        expectOffset(zone, DateTime(2027, 11, 7), -5);
      }
      expectOffset('America/Los_Angeles', DateTime(2026, 3, 7), -8);
      expectOffset('America/Los_Angeles', DateTime(2026, 3, 8), -7);
      expectOffset('America/Los_Angeles', DateTime(2026, 11, 1), -8);
    });

    test('EU/UK: DST from the last Sunday of March to the last Sunday of October', () {
      for (final (zone, base) in [('Europe/London', 0.0), ('Europe/Paris', 1.0), ('Europe/Berlin', 1.0)]) {
        expectOffset(zone, DateTime(2026, 3, 28), base);
        expectOffset(zone, DateTime(2026, 3, 29), base + 1);
        expectOffset(zone, DateTime(2026, 10, 24), base + 1);
        expectOffset(zone, DateTime(2026, 10, 25), base);
        expectOffset(zone, DateTime(2027, 3, 27), base);
        expectOffset(zone, DateTime(2027, 3, 28), base + 1);
        expectOffset(zone, DateTime(2027, 10, 30), base + 1);
        expectOffset(zone, DateTime(2027, 10, 31), base);
      }
    });

    test('Australia (southern hemisphere): DST from the 1st Sunday of October to the 1st Sunday of April', () {
      expectOffset('Australia/Sydney', DateTime(2026, 10, 3), 10);
      expectOffset('Australia/Sydney', DateTime(2026, 10, 4), 11);
      expectOffset('Australia/Sydney', DateTime(2027, 4, 3), 11);
      expectOffset('Australia/Sydney', DateTime(2027, 4, 4), 10);
    });

    test('no DST: Saudi Arabia, Gulf, Pakistan, Turkey, Jordan, Syria, Indonesia, Malaysia', () {
      const fixed = {
        'Asia/Riyadh': 3.0,
        'Asia/Dubai': 4.0,
        'Asia/Kuwait': 3.0,
        'Asia/Qatar': 3.0,
        'Asia/Karachi': 5.0,
        'Europe/Istanbul': 3.0, // permanent +03 since 2016
        'Asia/Amman': 3.0, // permanent +03 since 2022
        'Asia/Damascus': 3.0, // permanent +03 since 2022
        'Asia/Jakarta': 7.0,
        'Asia/Kuala_Lumpur': 8.0,
        'Africa/Lagos': 1.0,
        'Africa/Algiers': 1.0,
        'Africa/Tunis': 1.0,
      };
      fixed.forEach((zone, h) {
        for (final d in [DateTime(2027, 1, 15), DateTime(2027, 7, 15)]) {
          expectOffset(zone, d, h);
        }
      });
    });

    test('Egypt: DST is back since 2023 (+02 in winter, +03 in summer)', () {
      expectOffset('Africa/Cairo', DateTime(2027, 1, 15), 2);
      expectOffset('Africa/Cairo', DateTime(2027, 7, 15), 3);
      expect(_transitionDays(tz.getLocation('Africa/Cairo'), DateTime.utc(2027), DateTime.utc(2028)).length, 2);
    });

    test('Morocco: every Moroccan city shows +00 since 2026-09-20 (IANA tzdata 2026c)', () {
      // IANA tzdata 2026c (2026-07-08, https://www.iana.org/time-zones/releases/2026c):
      // "Morocco plans to move back to permanent UTC, without daylight saving time
      // transitions, on 2026-09-20 at 02:00." The bundled timezone 0.10.1 predates it, so
      // cityLocation() replaces the stale zone (lib/features/prayer/city_time_zone.dart).
      final moroccan = cities.where((c) => c.countryId == 'ma').toList();
      expect(moroccan.map((c) => c.id), containsAll(['rabat', 'casa', 'marrakech', 'fes', 'tangier']));
      for (final city in moroccan) {
        final loc = cityLocation(city);
        for (final d in [
          DateTime(2026, 9, 21),
          DateTime(2026, 11, 22),
          DateTime(2027, 2, 20), // Ramadan 1448: no Ramadan change any more
          DateTime(2027, 6, 1),
          DateTime(2028, 3, 1),
        ]) {
          expect(_offsetAtNoon(loc, d), Duration.zero, reason: '${city.id} on $d');
        }
        // Wall clock = UTC: Dhuhr in late November is about 12:05-12:20 across Morocco (not 13:xx).
        final dhuhr = prayerInstantsOn(
          location: loc,
          year: 2026,
          month: 11,
          day: 22,
          lat: city.lat,
          lng: city.lng,
          method: methodById('morocco'),
        )[Prayer.dhuhr]!;
        expect(dhuhr.timeZoneOffset, Duration.zero, reason: city.id);
        expect(dhuhr.hour, 12, reason: '${city.id}: Dhuhr $dhuhr');
      }
    });

    test('the Morocco correction touches no other city', () {
      for (final city in cities.where((c) => c.countryId != 'ma')) {
        expect(cityLocation(city).name, city.timeZone, reason: city.id);
      }
      // And it switches itself off once the bundled data is current (+00 after the change).
      final casa = cityLocation(cityById('casa'));
      final raw = tz.getLocation('Africa/Casablanca');
      final rawIsCurrent = _offsetAtNoon(raw, DateTime(2026, 11, 22)) == Duration.zero;
      expect(casa.name, rawIsCurrent ? 'Africa/Casablanca' : 'UTC');
    });
  });

  group('DST switch days', () {
    final from = DateTime.utc(2026, 1, 1);
    final to = DateTime.utc(2028, 1, 1);
    final dstCities = [
      for (final city in cities)
        if (_transitionDays(tz.getLocation(city.timeZone), from, to).isNotEmpty) WorldCase.catalog(city.id),
    ];

    test('the catalog has DST cities on both hemispheres and in the Middle East', () {
      final ids = dstCities.map((c) => c.city.id).toSet();
      expect(ids, containsAll(['nyc', 'toronto', 'la', 'london', 'paris', 'berlin', 'sydney', 'cairo', 'beirut', 'gaza']));
      expect(ids, isNot(contains('makkah')));
    });

    test('on, before and after every switch: right instants, wall clock jumps by exactly the DST change', () {
      final problems = <String>[];
      for (final c in dstCities) {
        final loc = tz.getLocation(c.city.timeZone);
        for (final day in _transitionDays(loc, from, to)) {
          final before = DateTime.utc(day.year, day.month, day.day - 1);
          final after = DateTime.utc(day.year, day.month, day.day + 1);
          final shift = (_offsetAtNoon(loc, day) - _offsetAtNoon(loc, before)).inMinutes;
          for (final d in [before, day, after]) {
            final t = _instants(c, d);
            for (final p in Prayer.values) {
              final got = t[p];
              final ref = _refInstant(c, d, p);
              if (got == null || ref == null) continue; // high-latitude summer, covered elsewhere
              if (_minutesApart(got, ref) > c.toleranceMinutes) problems.add('$c $d $p: $got vs reference ${ref.toIso8601String()}');
              // The switch happens at night before Fajr, so every prayer of the day is in
              // that day's (post-switch) offset.
              if (got.timeZoneOffset != _offsetAtNoon(loc, d)) problems.add('$c $d $p: offset ${got.timeZoneOffset}');
            }
          }
          // Dhuhr moves < 1 min/day by itself, so the wall-clock jump is the DST change.
          final dBefore = _instants(c, before)[Prayer.dhuhr]!;
          final dDay = _instants(c, day)[Prayer.dhuhr]!;
          final jump = (_wallHours(dDay) - _wallHours(dBefore)) * 60;
          if ((jump - shift).abs() > 1.5) problems.add('$c $day: Dhuhr wall clock jumped ${jump.toStringAsFixed(1)} min, DST change is $shift min');
        }
      }
      expect(problems, isEmpty, reason: problems.take(30).join('\n'));
    });

    test('calculator with the day\'s noon offset (what the home screen does after the switch) agrees with the instants', () {
      for (final c in dstCities.where((c) => c.city.lat.abs() < 48)) {
        final loc = tz.getLocation(c.city.timeZone);
        for (final day in _transitionDays(loc, from, to)) {
          final wall = const PrayerCalculator().compute(
            date: day,
            lat: c.city.lat,
            lng: c.city.lng,
            utcOffsetHours: _offsetAtNoon(loc, day).inMinutes / 60,
            method: c.method,
            asrFactor: c.asrFactor,
          );
          final t = _instants(c, day);
          for (final p in Prayer.values) {
            expect(wall.of(p) * 60, closeTo(_wallHours(t[p]!) * 60, 0.51), reason: '$c $day $p');
          }
        }
      }
    });
  });

  group('adhan notification plan', () {
    final nyc = WorldCase.catalog('nyc');
    final ny = tz.getLocation('America/New_York');

    List<AdhanSlot> plan(WorldCase c, tz.TZDateTime now) => planAdhanNotifications(
          now: now,
          lat: c.city.lat,
          lng: c.city.lng,
          method: c.method,
          asrFactor: c.asrFactor,
        );

    void expectMatchesReference(WorldCase c, List<AdhanSlot> slots) {
      for (final s in slots) {
        final d = DateTime.utc(s.when.year, s.when.month, s.when.day);
        // Isha can be after local midnight; then it belongs to the previous day.
        final ref = _refInstant(c, d, s.prayer) ?? _refInstant(c, DateTime.utc(d.year, d.month, d.day - 1), s.prayer);
        expect(ref, isNotNull, reason: '$c ${s.prayer} ${s.when}');
        expect(_minutesApart(s.when, ref!), lessThanOrEqualTo(c.toleranceMinutes), reason: '$c ${s.prayer} ${s.when} vs $ref');
      }
    }

    void expectWellFormed(List<AdhanSlot> slots, tz.TZDateTime now) {
      expect(slots.map((s) => s.id).toSet().length, slots.length, reason: 'ids must be unique');
      for (var i = 0; i < slots.length; i++) {
        expect(slots[i].when.isAfter(now), isTrue);
        if (i > 0) expect(slots[i].when.isAfter(slots[i - 1].when), isTrue, reason: 'chronological');
      }
    }

    test('US spring forward: Sunday adhans planned on Saturday are at the right instant (regression)', () {
      final now = tz.TZDateTime(ny, 2026, 3, 7, 10);
      final slots = plan(nyc, now);
      expectWellFormed(slots, now);
      expectMatchesReference(nyc, slots);
      final sunday = slots.where((s) => s.when.day == 8).toList();
      expect(sunday.map((s) => s.prayer), Prayer.values);
      // Dhuhr in New York on 8 March 2026 is ~13:08 EDT. The old "local midnight +
      // hours" arithmetic scheduled it at ~14:08 (one hour late).
      final dhuhr = sunday.firstWhere((s) => s.prayer == Prayer.dhuhr).when;
      expect(dhuhr.hour, 13);
      expect(dhuhr.timeZoneOffset, const Duration(hours: -4));
    });

    test('US spring forward: planning late on Saturday still covers Sunday (no "+24 h" skip)', () {
      // 23:30 EST + 24 h = 00:30 EDT on Monday: the old code planned Monday and never Sunday.
      final now = tz.TZDateTime(ny, 2026, 3, 7, 23, 30);
      final slots = plan(nyc, now);
      expectWellFormed(slots, now);
      expect(slots, hasLength(5));
      expect(slots.every((s) => s.when.day == 8), isTrue);
      expect(slots.first.prayer, Prayer.fajr);
      expectMatchesReference(nyc, slots);
    });

    test('US fall back: Sunday adhans are not one hour early (regression)', () {
      final now = tz.TZDateTime(ny, 2026, 10, 31, 10);
      final slots = plan(nyc, now);
      expectWellFormed(slots, now);
      expectMatchesReference(nyc, slots);
      final dhuhr = slots.firstWhere((s) => s.when.day == 1 && s.prayer == Prayer.dhuhr).when;
      expect(dhuhr.hour, 11); // ~11:41 EST
      expect(dhuhr.timeZoneOffset, const Duration(hours: -5));
    });

    test('every DST switch in 2026-2027, every DST city: plan made the day before is right', () {
      for (final city in cities) {
        final c = WorldCase.catalog(city.id);
        final loc = tz.getLocation(city.timeZone);
        for (final day in _transitionDays(loc, DateTime.utc(2026, 1, 1), DateTime.utc(2028, 1, 1))) {
          for (final hour in [0, 12, 23]) {
            final prev = DateTime.utc(day.year, day.month, day.day - 1);
            final now = tz.TZDateTime(loc, prev.year, prev.month, prev.day, hour, 30);
            final slots = plan(c, now);
            expectWellFormed(slots, now);
            expectMatchesReference(c, slots);
          }
        }
      }
    });

    test('UK and Australia switches: London 28 Mar 2027, Sydney 4 Oct 2026', () {
      final london = WorldCase.catalog('london');
      final lon = tz.getLocation('Europe/London');
      final l = plan(london, tz.TZDateTime(lon, 2027, 3, 27, 22));
      expectMatchesReference(london, l);
      expect(l.firstWhere((s) => s.prayer == Prayer.dhuhr).when.timeZoneOffset, const Duration(hours: 1));

      final sydney = WorldCase.catalog('sydney');
      final syd = tz.getLocation('Australia/Sydney');
      final s = plan(sydney, tz.TZDateTime(syd, 2026, 10, 3, 22));
      expectMatchesReference(sydney, s);
      expect(s.firstWhere((x) => x.prayer == Prayer.dhuhr).when.timeZoneOffset, const Duration(hours: 11));
    });

    test('across midnight: after Isha the next adhan is tomorrow\'s Fajr', () {
      final makkah = WorldCase.catalog('makkah');
      final loc = tz.getLocation('Asia/Riyadh');
      final now = tz.TZDateTime(loc, 2026, 11, 22, 23, 59);
      final slots = plan(makkah, now);
      expectWellFormed(slots, now);
      expect(slots, hasLength(5));
      expect(slots.first.prayer, Prayer.fajr);
      expect((slots.first.when.month, slots.first.when.day), (11, 23));
      expectMatchesReference(makkah, slots);
    });

    test('a prayer exactly "now" is not re-planned; one minute earlier it is', () {
      final cairo = WorldCase.catalog('cairo');
      final loc = tz.getLocation('Africa/Cairo');
      final asr = _instants(cairo, DateTime.utc(2027, 5, 10))[Prayer.asr]!;
      expect(plan(cairo, asr).first.prayer, Prayer.maghrib);
      expect(plan(cairo, tz.TZDateTime.from(asr.subtract(const Duration(minutes: 1)), loc)).first.prayer, Prayer.asr);
    });

    test('year boundary: Dubai on 31 Dec plans 1 Jan 2027', () {
      final dubai = WorldCase.catalog('dubai');
      final now = tz.TZDateTime(tz.getLocation('Asia/Dubai'), 2026, 12, 31, 22);
      final slots = plan(dubai, now);
      expectWellFormed(slots, now);
      expect(slots, hasLength(5));
      expect(slots.every((s) => s.when.year == 2027 && s.when.month == 1 && s.when.day == 1), isTrue);
      expectMatchesReference(dubai, slots);
    });

    test('leap day: Cairo on 28 Feb 2028 plans 29 Feb 2028', () {
      final cairo = WorldCase.catalog('cairo');
      final now = tz.TZDateTime(tz.getLocation('Africa/Cairo'), 2028, 2, 28, 21);
      final slots = plan(cairo, now);
      expect(slots, hasLength(5));
      expect(slots.every((s) => s.when.month == 2 && s.when.day == 29), isTrue);
      expectMatchesReference(cairo, slots);
    });

    test('Ramadan 1448 (Feb-Mar 2027): Makkah, Cairo, Jakarta, Casablanca stay correct', () {
      for (final id in ['makkah', 'cairo', 'jakarta', 'casa']) {
        final c = WorldCase.catalog(id);
        final loc = tz.getLocation(c.city.timeZone);
        for (final d in [DateTime(2027, 2, 7), DateTime(2027, 2, 20), DateTime(2027, 3, 8)]) {
          final now = tz.TZDateTime(loc, d.year, d.month, d.day, 12);
          final slots = plan(c, now);
          expectWellFormed(slots, now);
          expectMatchesReference(c, slots);
        }
      }
    });

    test('traveller: the phone\'s own time zone does not change the plan', () {
      // A family in London that picked Makkah gets the adhan at Makkah's prayer moment
      // (shown in Makkah time in the app); the phone shows it in its own local time.
      final makkah = WorldCase.catalog('makkah');
      final riyadh = tz.getLocation('Asia/Riyadh');
      final now = tz.TZDateTime(riyadh, 2027, 3, 27, 9);
      final results = <List<int>>[];
      try {
        for (final device in ['Europe/London', 'Asia/Tokyo', 'America/Los_Angeles']) {
          tz.setLocalLocation(tz.getLocation(device));
          final slots = plan(makkah, now);
          for (final s in slots) {
            expect(s.when.location.name, 'Asia/Riyadh');
            expect(s.when.timeZoneOffset, const Duration(hours: 3));
          }
          results.add([for (final s in slots) s.when.millisecondsSinceEpoch]);
        }
      } finally {
        tz.setLocalLocation(tz.UTC);
      }
      expect(results[1], results[0]);
      expect(results[2], results[0]);
    });

    test('next adhan in the plan matches the home screen\'s "next prayer" all day long', () {
      for (final id in ['makkah', 'cairo', 'karachi', 'nyc', 'sydney', 'jakarta']) {
        final c = WorldCase.catalog(id);
        final loc = tz.getLocation(c.city.timeZone);
        final day = DateTime(2027, 1, 20);
        final wall = const PrayerCalculator().compute(
          date: day,
          lat: c.city.lat,
          lng: c.city.lng,
          utcOffsetHours: _offsetAtNoon(loc, day).inMinutes / 60,
          method: c.method,
          asrFactor: c.asrFactor,
        );
        for (var minute = 0; minute < 1440; minute += 7) {
          // At hh:mm:30 so the plan's whole-minute rounding never ties with "now".
          final now = tz.TZDateTime(loc, day.year, day.month, day.day, minute ~/ 60, minute % 60, 30);
          final next = wall.nextAfter(now.hour + now.minute / 60 + 30 / 3600);
          expect(plan(c, now).first.prayer, next, reason: '$c at $now');
        }
      }
    });

    test('high latitude summer: no Fajr/Isha adhan in London (documented gap), others planned', () {
      final london = WorldCase.catalog('london');
      final now = tz.TZDateTime(tz.getLocation('Europe/London'), 2026, 6, 21);
      final slots = plan(london, now);
      expect(slots.map((s) => s.prayer).toSet(), {Prayer.dhuhr, Prayer.asr, Prayer.maghrib});
      expectMatchesReference(london, slots);
    });
  });

  group('next prayer', () {
    test('wraps to Fajr after Isha, also when Isha is after midnight', () {
      const t = PrayerTimes([3.1, 13.1, 17.4, 21.3, 24.4]); // Isha 00:24 next day
      expect(t.nextAfter(23.9), Prayer.isha);
      expect(t.nextAfter(24.5), Prayer.fajr);
      expect(t.nextAfter(0), Prayer.fajr);
    });

    test('skips a missing (NaN) prayer', () {
      const t = PrayerTimes([double.nan, 13.1, 17.4, 21.3, double.nan]);
      expect(t.nextAfter(1), Prayer.dhuhr);
      expect(t.nextAfter(22), Prayer.fajr); // wraps; Fajr itself has no time -> UI shows "--"
    });

    test('reference sanity: Makkah transit and sunrise are where they should be', () {
      // Guards the reference itself: Makkah (39.86°E, UTC+3) has solar noon between
      // about 12:04 and 12:35 local all year and sunrise between about 05:35 and 07:02.
      for (final d in worldDates) {
        final r = SolarReference.day(
          year: d.year,
          month: d.month,
          day: d.day,
          lat: 21.3891,
          lng: 39.8579,
          fajrAngle: 18.5,
          ishaMinutesAfterMaghrib: 90,
        );
        final noonLocal = r.transit + 180;
        expect(noonLocal, inInclusiveRange(12 * 60 + 3, 12 * 60 + 37), reason: '$d');
        expect(r.sunrise! + 180, inInclusiveRange(5 * 60 + 30, 7 * 60 + 10), reason: '$d');
      }
    });
  });
}
