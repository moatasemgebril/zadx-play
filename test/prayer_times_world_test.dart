// Prayer times around the world: the app's calculator against an independent
// astronomical reference (NOAA / Meeus, see test/support/solar_reference.dart),
// plus invariants that must hold for every city on every date.
//
// No "official timetable" numbers are invented here. Each value is compared with the
// reference computed from first principles for the same method angles; the method
// angles themselves are pinned in the "method table" test with their sources.
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:zadx/data/catalog/locations.dart';
import 'package:zadx/core/localized.dart';
import 'package:zadx/data/models/location.dart';
import 'package:zadx/features/prayer/city_time_zone.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_schedule.dart';

import 'support/prayer_cases.dart';
import 'support/solar_reference.dart';

/// Angle-based Fajr/Isha are compared strictly only when the sun goes at least this
/// many degrees below the method's angle during the night. Closer to the limit the
/// time becomes extremely sensitive (at London 17° Isha in late May moves ~10 minutes
/// for 0.05° of solar declination), so two correct algorithms legitimately disagree.
const _minTwilightMarginDegrees = 3.0;

String _hm(double minutesUtc) {
  final m = minutesUtc.round() % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}Z';
}

String _d(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  tzdata.initializeTimeZones();

  group('app vs astronomical reference (NOAA/Meeus)', () {
    for (final c in worldCases) {
      test('$c on ${worldDates.length} dates', () {
        final problems = <String>[];
        final tol = c.toleranceMinutes;

        void cmp(String what, DateTime date, double app, double? ref, {double extra = 0}) {
          if (ref == null || !app.isFinite) {
            problems.add('${_d(date)} $what: app=${app.isFinite ? _hm(app) : 'NaN'} ref=${ref == null ? 'none' : _hm(ref)}');
            return;
          }
          final diff = (app - (ref + extra)).abs();
          if (diff > tol) {
            problems.add('${_d(date)} $what: app=${_hm(app)} ref=${_hm(ref + extra)} diff=${diff.toStringAsFixed(1)} min');
          }
        }

        void cmpAngle(String what, DateTime date, double app, double? ref, double angle) {
          final margin = SolarReference.twilightMargin(
            year: date.year,
            month: date.month,
            day: date.day,
            lat: c.city.lat,
            lng: c.city.lng,
            angle: angle,
          );
          if (!app.isFinite || ref == null) {
            // Both must agree that the sun never reaches the angle, except right at the limit.
            if (app.isFinite != (ref != null) && margin.abs() > 1) {
              problems.add('${_d(date)} $what: app ${app.isFinite ? 'has a time' : 'NaN'} but reference '
                  '${ref == null ? 'has none' : 'has ${_hm(ref)}'} (margin ${margin.toStringAsFixed(2)}°)');
            }
            return;
          }
          if (margin < _minTwilightMarginDegrees) return; // too close to the limit, see above
          cmp(what, date, app, ref);
        }

        for (final date in worldDates) {
          final app = appUtcMinutes(c, date);
          final ref = referenceFor(c, date);
          cmpAngle('Fajr', date, app[Prayer.fajr.index], ref.fajr, c.method.fajrAngle);
          cmp('Dhuhr', date, app[Prayer.dhuhr.index], ref.transit, extra: 1);
          cmp('Asr', date, app[Prayer.asr.index], ref.asr);
          cmp('Maghrib', date, app[Prayer.maghrib.index], ref.maghrib);
          if (c.method.ishaMinutesAfterMaghrib != null) {
            cmp('Isha', date, app[Prayer.isha.index], ref.isha);
          } else {
            cmpAngle('Isha', date, app[Prayer.isha.index], ref.isha, c.method.ishaAngle!);
          }
          // The other Asr school too (Hanafi for most cities, Shafi'i for Karachi).
          final otherAsr = c.asrFactor == 1 ? 2 : 1;
          cmp(
            'Asr(x$otherAsr)',
            date,
            appUtcMinutes(c, date, asrFactor: otherAsr)[Prayer.asr.index],
            referenceFor(c, date, asrFactor: otherAsr).asr,
          );
        }
        expect(problems, isEmpty, reason: '$c (tolerance ±$tol min)');
      });
    }
  });

  group('invariants for every city and date', () {
    // Every catalog city with its country default, plus the extra world cities.
    final all = <WorldCase>[
      for (final city in cities) WorldCase.catalog(city.id),
      for (final c in worldCases)
        if (!c.inCatalog) c,
    ];

    test('order, finiteness, Dhuhr at solar noon, sunrise inside Fajr..Dhuhr, Hanafi Asr later', () {
      final problems = <String>[];
      for (final c in all) {
        final loc = tz.getLocation(c.city.timeZone);
        for (final date in worldDates) {
          final where = '$c ${_d(date)}';
          final shafii = prayerInstantsOn(
            location: loc,
            year: date.year,
            month: date.month,
            day: date.day,
            lat: c.city.lat,
            lng: c.city.lng,
            method: c.method,
          );
          final hanafi = prayerInstantsOn(
            location: loc,
            year: date.year,
            month: date.month,
            day: date.day,
            lat: c.city.lat,
            lng: c.city.lng,
            method: c.method,
            asrFactor: 2,
          );
          final ref = referenceFor(c, date);

          // Dhuhr, Asr and Maghrib exist everywhere below the polar circle.
          for (final p in [Prayer.dhuhr, Prayer.asr, Prayer.maghrib]) {
            if (shafii[p] == null) problems.add('$where: $p missing');
          }
          // Strictly increasing (also means no duplicates).
          final present = [for (final p in Prayer.values) if (shafii[p] != null) (p, shafii[p]!)];
          for (var i = 1; i < present.length; i++) {
            if (!present[i].$2.isAfter(present[i - 1].$2)) {
              problems.add('$where: ${present[i].$1} (${present[i].$2}) not after ${present[i - 1].$1} (${present[i - 1].$2})');
            }
          }
          // Fajr < sunrise < Dhuhr (the app has no sunrise of its own; use the reference).
          final dayUtc = DateTime.utc(date.year, date.month, date.day);
          final sunrise = ref.sunrise == null ? null : dayUtc.add(Duration(seconds: (ref.sunrise! * 60).round()));
          if (sunrise != null) {
            final fajr = shafii[Prayer.fajr];
            if (fajr != null && !fajr.isBefore(sunrise)) problems.add('$where: Fajr $fajr not before sunrise $sunrise');
            if (!shafii[Prayer.dhuhr]!.isAfter(sunrise)) problems.add('$where: Dhuhr not after sunrise');
          }
          // Dhuhr = solar transit + 1 min (±1 min for rounding).
          final transit = dayUtc.add(Duration(seconds: (ref.transit * 60).round()));
          final dhuhrDiff = shafii[Prayer.dhuhr]!.difference(transit).inSeconds / 60;
          if ((dhuhrDiff - 1).abs() > 1.01) problems.add('$where: Dhuhr is ${dhuhrDiff.toStringAsFixed(1)} min from transit');
          // Dhuhr on the city's wall clock is a sensible midday time.
          final dh = shafii[Prayer.dhuhr]!;
          final dhuhrWall = dh.hour + dh.minute / 60;
          if (dhuhrWall < 11 || dhuhrWall > 14.5) problems.add('$where: Dhuhr at wall clock $dh');
          // Every prayer falls on the city's own calendar day. Exceptions: Isha may be just
          // after midnight, and above 60° (Reykjavik) even Maghrib is after midnight in June.
          for (final (p, t) in present) {
            final sameDay = t.year == date.year && t.month == date.month && t.day == date.day;
            final mayCross = p == Prayer.isha || (p == Prayer.maghrib && c.city.lat.abs() > 60);
            if (!sameDay && !mayCross) problems.add('$where: $p falls on ${t.toString()}');
          }
          // Hanafi Asr (shadow x2) is later than Shafi'i Asr (shadow x1) and before Maghrib.
          final a1 = shafii[Prayer.asr]!, a2 = hanafi[Prayer.asr]!;
          if (!a2.isAfter(a1)) problems.add('$where: Hanafi Asr $a2 not after Shafi\'i Asr $a1');
          if (!a2.isBefore(shafii[Prayer.maghrib]!)) problems.add('$where: Hanafi Asr not before Maghrib');
          // Fixed-interval Isha methods (Umm al-Qura, Qatar).
          final fixed = c.method.ishaMinutesAfterMaghrib;
          if (fixed != null) {
            final gap = shafii[Prayer.isha]!.difference(shafii[Prayer.maghrib]!).inMinutes;
            if ((gap - fixed).abs() > 1) problems.add('$where: Isha is $gap min after Maghrib, expected $fixed');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.take(30).join('\n'));
    });

    test('times change smoothly from day to day (year boundary, leap day, whole 2027)', () {
      // Day-indexing bugs (off-by-one day, wrong Julian date, leap-year slips) show up
      // as jumps. Instants are compared in UTC so DST does not count as a jump.
      final problems = <String>[];
      for (final c in worldCases.where((c) => c.city.lat.abs() < 48)) {
        final loc = tz.getLocation(c.city.timeZone);
        Map<Prayer, tz.TZDateTime?> on(DateTime d) => prayerInstantsOn(
              location: loc,
              year: d.year,
              month: d.month,
              day: d.day,
              lat: c.city.lat,
              lng: c.city.lng,
              method: c.method,
              asrFactor: c.asrFactor,
            );
        final spans = [
          (DateTime.utc(2026, 12, 25), 14), // across 2026 -> 2027
          (DateTime.utc(2028, 2, 25), 10), // across 2028-02-29
          (DateTime.utc(2027, 1, 1), 365), // a whole year
        ];
        for (final (start, days) in spans) {
          var prev = on(start);
          for (var i = 1; i <= days; i++) {
            final d = DateTime.utc(start.year, start.month, start.day + i);
            final cur = on(d);
            for (final p in Prayer.values) {
              final step = cur[p]!.difference(prev[p]!).inSeconds / 60 - 1440;
              if (step.abs() > 4) problems.add('$c ${_d(d)} $p moved ${step.toStringAsFixed(1)} min vs previous day');
            }
            prev = cur;
          }
        }
      }
      expect(problems, isEmpty, reason: problems.take(30).join('\n'));
    });

    test('every catalog city: local noon and Dhuhr fall on the same calendar day as UTC noon', () {
      // prayer_schedule.dart computes "UTC day D" and places it in the city's zone; that is
      // the city's day D only while the zone is within ±12 h of UTC (no date-line zones
      // such as Pacific/Kiritimati +14). Guard it for every catalog city.
      final problems = <String>[];
      for (final city in cities) {
        for (final loc in {tz.getLocation(city.timeZone), cityLocation(city)}) {
          for (final date in worldDates) {
            final noon = tz.TZDateTime.from(DateTime.utc(date.year, date.month, date.day, 12), loc);
            if ((noon.year, noon.month, noon.day) != (date.year, date.month, date.day)) {
              problems.add('${city.id} (${loc.name}) ${_d(date)}: UTC noon is $noon locally');
            }
            if (noon.timeZoneOffset.inMinutes.abs() >= 12 * 60) {
              problems.add('${city.id} (${loc.name}) ${_d(date)}: offset ${noon.timeZoneOffset}');
            }
            final dhuhr = prayerInstantsOn(
              location: loc,
              year: date.year,
              month: date.month,
              day: date.day,
              lat: city.lat,
              lng: city.lng,
              method: methodById(countryById(city.countryId).methodId),
            )[Prayer.dhuhr]!;
            if ((dhuhr.year, dhuhr.month, dhuhr.day) != (date.year, date.month, date.day)) {
              problems.add('${city.id} (${loc.name}) ${_d(date)}: Dhuhr is $dhuhr locally');
            }
          }
        }
      }
      expect(problems, isEmpty, reason: problems.take(30).join('\n'));
    });

    test('leap day 2028-02-29 is computed as its own day between Feb 28 and Mar 1', () {
      final cairo = WorldCase.catalog('cairo');
      final loc = tz.getLocation(cairo.city.timeZone);
      final feb29 = prayerInstantsOn(
        location: loc,
        year: 2028,
        month: 2,
        day: 29,
        lat: cairo.city.lat,
        lng: cairo.city.lng,
        method: cairo.method,
      );
      for (final t in feb29.values) {
        expect(t, isNotNull);
        expect((t!.month, t.day), (2, 29));
      }
      // Overflow form (Feb 30 -> Mar 1) gives the same result as Mar 1.
      final mar1 = prayerInstantsOn(
        location: loc,
        year: 2028,
        month: 3,
        day: 1,
        lat: cairo.city.lat,
        lng: cairo.city.lng,
        method: cairo.method,
      );
      final feb30 = prayerInstantsOn(
        location: loc,
        year: 2028,
        month: 2,
        day: 30,
        lat: cairo.city.lat,
        lng: cairo.city.lng,
        method: cairo.method,
      );
      for (final p in Prayer.values) {
        expect(feb30[p], mar1[p]);
      }
    });
  });

  group('high latitudes', () {
    final north = worldCases.where((c) => c.city.lat >= 48).toList();
    final summer = [
      DateTime.utc(2026, 5, 20),
      DateTime.utc(2026, 6, 21),
      DateTime.utc(2026, 7, 10),
      DateTime.utc(2027, 6, 21),
    ];

    test('summer nights (London, Paris, Berlin, Stockholm, Oslo, Reykjavik): no crash, no invalid order', () {
      for (final c in north) {
        final loc = tz.getLocation(c.city.timeZone);
        for (final date in summer) {
          final t = prayerInstantsOn(
            location: loc,
            year: date.year,
            month: date.month,
            day: date.day,
            lat: c.city.lat,
            lng: c.city.lng,
            method: c.method,
          );
          final raw = appUtcMinutes(c, date);
          for (final v in raw) {
            expect(v.isInfinite, isFalse, reason: '$c ${_d(date)}'); // NaN = "no time", never ±Infinity
          }
          for (final p in [Prayer.dhuhr, Prayer.asr, Prayer.maghrib]) {
            expect(t[p], isNotNull, reason: '$c ${_d(date)} $p');
          }
          final present = [for (final p in Prayer.values) if (t[p] != null) t[p]!];
          for (var i = 1; i < present.length; i++) {
            expect(present[i].isAfter(present[i - 1]), isTrue, reason: '$c ${_d(date)}');
          }
          final plan = planAdhanNotifications(
            now: tz.TZDateTime(loc, date.year, date.month, date.day),
            lat: c.city.lat,
            lng: c.city.lng,
            method: c.method,
          );
          expect(plan.map((s) => s.when.millisecondsSinceEpoch).toSet().length, plan.length);
        }
      }
    });

    test('without a rule: London MWL has no Fajr/Isha around the June solstice', () {
      // The sun stays above -18° all night in London from about 21 May to 23 July, and
      // above -17° from about 27 May to 17 July. Without a high-latitude rule these
      // prayers are missing; the app's default rule (below) fills them in.
      final london = WorldCase.catalog('london');
      final raw = appUtcMinutes(london, DateTime.utc(2026, 6, 21));
      expect(raw[Prayer.fajr.index].isNaN, isTrue);
      expect(raw[Prayer.isha.index].isNaN, isTrue);
    });

    test('default setting: twilight angle from 48° latitude, no rule below', () {
      expect(HighLatitudeSetting.parse(null), HighLatitudeSetting.auto);
      expect(HighLatitudeSetting.parse('nonsense'), HighLatitudeSetting.auto);
      for (final v in HighLatitudeSetting.values) {
        expect(HighLatitudeSetting.parse(v.name), v);
      }
      const auto = HighLatitudeSetting.auto;
      expect(resolveHighLatitudeRule(auto, 51.5074), HighLatitudeRule.twilightAngle); // London
      expect(resolveHighLatitudeRule(auto, 48.0), HighLatitudeRule.twilightAngle);
      expect(resolveHighLatitudeRule(auto, -48.0), HighLatitudeRule.twilightAngle);
      expect(resolveHighLatitudeRule(auto, 47.99), isNull);
      expect(resolveHighLatitudeRule(auto, 30.0444), isNull); // Cairo
      // An explicit parent choice applies at any latitude.
      expect(resolveHighLatitudeRule(HighLatitudeSetting.middleOfTheNight, 30), HighLatitudeRule.middleOfTheNight);
      expect(resolveHighLatitudeRule(HighLatitudeSetting.seventhOfTheNight, 30), HighLatitudeRule.seventhOfTheNight);
      expect(resolveHighLatitudeRule(HighLatitudeSetting.twilightAngle, 30), HighLatitudeRule.twilightAngle);
    });

    test('Fajr and Isha exist on every day of the year in every catalog city (default setting)', () {
      final problems = <String>[];
      for (final city in cities) {
        final c = WorldCase.catalog(city.id);
        final rule = resolveHighLatitudeRule(HighLatitudeSetting.auto, city.lat);
        for (var i = 0; i < 365; i++) {
          final raw = appUtcMinutes(c, DateTime.utc(2026, 1, 1 + i), highLatitudeRule: rule);
          if (raw.any((v) => !v.isFinite)) problems.add('${city.id} day ${i + 1}');
          for (var k = 1; k < raw.length; k++) {
            if (!(raw[k] > raw[k - 1])) problems.add('${city.id} day ${i + 1}: ${Prayer.values[k]} not after ${Prayer.values[k - 1]}');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.take(20).join(', '));
    });

    final hlCases = [
      WorldCase.catalog('london'),
      worldCases.firstWhere((c) => c.city.id == 'test-oslo'),
      worldCases.firstWhere((c) => c.city.id == 'test-reykjavik'),
    ];
    final hlDates = [
      DateTime.utc(2026, 6, 21),
      DateTime.utc(2026, 5, 20),
      DateTime.utc(2026, 7, 10),
      DateTime.utc(2026, 12, 21),
    ];

    for (final rule in HighLatitudeRule.values) {
      test('${rule.name}: London (21 Jun), Oslo, Reykjavik have Fajr/Isha, in order, by the night-portion definition', () {
        final problems = <String>[];
        for (final c in hlCases) {
          final tol = c.toleranceMinutes;
          final (fajrPortion, ishaPortion) = switch (rule) {
            HighLatitudeRule.middleOfTheNight => (1 / 2, 1 / 2),
            HighLatitudeRule.seventhOfTheNight => (1 / 7, 1 / 7),
            HighLatitudeRule.twilightAngle => (c.method.fajrAngle / 60, c.method.ishaAngle! / 60),
          };
          for (final date in hlDates) {
            final where = '$c ${_d(date)}';
            final app = appUtcMinutes(c, date, highLatitudeRule: rule);
            final next = appUtcMinutes(c, DateTime.utc(date.year, date.month, date.day + 1), highLatitudeRule: rule);
            final plain = appUtcMinutes(c, date);
            if (app.any((v) => !v.isFinite)) {
              problems.add('$where: missing/invalid time $app');
              continue;
            }
            for (var k = 1; k < app.length; k++) {
              if (!(app[k] > app[k - 1])) problems.add('$where: ${Prayer.values[k]} not after ${Prayer.values[k - 1]}');
            }
            // Isha is before the next day's Fajr. With middleOfTheNight both are at the middle
            // of (slightly different) nights, so they may cross by half the day-to-day change
            // of sunrise + sunset (a few minutes at 64° N in July); the adhan plan handles it.
            final gapToNextFajr = next[Prayer.fajr.index] + 1440 - app[Prayer.isha.index];
            if (rule == HighLatitudeRule.middleOfTheNight ? gapToNextFajr < -6 : gapToNextFajr <= 0) {
              problems.add('$where: Isha ${_hm(app[Prayer.isha.index])} vs next Fajr ${_hm(next[Prayer.fajr.index])}');
            }

            // Night portions from the independent reference (sunset to next sunrise).
            final ref = referenceFor(c, date);
            final refNext = referenceFor(c, DateTime.utc(date.year, date.month, date.day + 1));
            final night = refNext.sunrise! + 1440 - ref.maghrib!;
            final safeFajr = ref.sunrise! - fajrPortion * night;
            final safeIsha = ref.maghrib! + ishaPortion * night;
            final fajr = app[Prayer.fajr.index], isha = app[Prayer.isha.index];
            if (fajr < safeFajr - tol) problems.add('$where: Fajr ${_hm(fajr)} earlier than the bound ${_hm(safeFajr)}');
            if (isha > safeIsha + tol) problems.add('$where: Isha ${_hm(isha)} later than the bound ${_hm(safeIsha)}');
            // Where the plain calculation has no time, the rule's time is the bound itself.
            if (plain[Prayer.fajr.index].isNaN && (fajr - safeFajr).abs() > tol) {
              problems.add('$where: Fajr ${_hm(fajr)}, expected ${_hm(safeFajr)}');
            }
            if (plain[Prayer.isha.index].isNaN && (isha - safeIsha).abs() > tol) {
              problems.add('$where: Isha ${_hm(isha)}, expected ${_hm(safeIsha)}');
            }
            // Dhuhr, Asr and Maghrib are never touched by the rule.
            for (final p in [Prayer.dhuhr, Prayer.asr, Prayer.maghrib]) {
              if (app[p.index] != plain[p.index]) problems.add('$where: $p changed by the rule');
            }

            // Adhan plan: Fajr and Isha are scheduled, strictly in order, never twice at once.
            final loc = tz.getLocation(c.city.timeZone);
            final plan = planAdhanNotifications(
              now: tz.TZDateTime(loc, date.year, date.month, date.day),
              lat: c.city.lat,
              lng: c.city.lng,
              method: c.method,
              highLatitudeRule: rule,
            );
            for (var i = 1; i < plan.length; i++) {
              if (!plan[i].when.isAfter(plan[i - 1].when)) problems.add('$where: adhan plan not increasing at $i');
            }
            final names = plan.map((s) => s.prayer.name).toList();
            // Fajr is always scheduled (both days start after `now` = local midnight, or Fajr is
            // within the first day); an Isha may only be left out when it is not before the next Fajr.
            if (plan.where((s) => s.prayer == Prayer.fajr).isEmpty) problems.add('$where: no Fajr adhan: $names');
            final ishas = plan.where((s) => s.prayer == Prayer.isha).length;
            if (rule != HighLatitudeRule.middleOfTheNight && ishas != 2) problems.add('$where: $ishas Isha adhans: $names');
            if (plan.length < 10 - (2 - ishas)) problems.add('$where: only ${plan.length} adhans in 2 days: $names');
            for (var i = 0; i + 1 < plan.length; i++) {
              if (plan[i].prayer == Prayer.isha && plan[i + 1].prayer == Prayer.fajr) {
                if (!plan[i + 1].when.isAfter(plan[i].when)) problems.add('$where: Isha adhan not before next Fajr');
              }
            }
          }
        }
        expect(problems, isEmpty, reason: problems.take(30).join('\n'));
      });
    }

    test('a fixed-interval Isha (Umm al-Qura) is never moved by a rule; only Fajr is bounded', () {
      // Makkah's method used in London on 21 June (e.g. a family that keeps Umm al-Qura abroad).
      const c = WorldCase(
        City(
          id: 'test-london-uaq',
          countryId: '',
          name: Localized('لندن', 'London'),
          lat: 51.5074,
          lng: -0.1278,
          timeZone: 'Europe/London',
        ),
        'makkah',
        inCatalog: false,
      );
      for (final rule in HighLatitudeRule.values) {
        final app = appUtcMinutes(c, DateTime.utc(2026, 6, 21), highLatitudeRule: rule);
        expect(app[Prayer.isha.index] - app[Prayer.maghrib.index], closeTo(90, 1e-6), reason: rule.name);
        expect(app[Prayer.fajr.index].isFinite, isTrue, reason: rule.name);
      }
    });
  });

  group('methods', () {
    test('method table matches the published angle definitions', () {
      // Sources: PrayTimes.org method table; adhan (batoulapps) CalculationMethod;
      // aladhan.com method list (Dubai 18.2/18.2, Kuwait 18/17.5, Qatar 18/90 min,
      // Diyanet 18/17, Kemenag 20/18, JAKIM 20/18, Algeria 18/17, Tunisia 18/18,
      // Morocco 19/17, Jordan 18/18, France UOIF 12/12).
      // Note: per-prayer minute offsets that some authorities add (Diyanet, Dubai,
      // Morocco, Jordan) are NOT modelled by the app; see the PR report.
      const expected = <String, (double, double?, int?)>{
        'egypt': (19.5, 17.5, null),
        'makkah': (18.5, null, 90),
        'mwl': (18, 17, null),
        'isna': (15, 15, null),
        'karachi': (18, 18, null),
        'dubai': (18.2, 18.2, null),
        'kuwait': (18, 17.5, null),
        'qatar': (18, null, 90),
        'jordan': (18, 18, null),
        'morocco': (19, 17, null),
        'turkey': (18, 17, null),
        'kemenag': (20, 18, null),
        'jakim': (20, 18, null),
        'algeria': (18, 17, null),
        'tunisia': (18, 18, null),
        'france': (12, 12, null),
      };
      expect(calcMethods.keys.toSet(), expected.keys.toSet());
      expected.forEach((id, e) {
        final m = methodById(id);
        expect((m.fajrAngle, m.ishaAngle, m.ishaMinutesAfterMaghrib), e, reason: id);
      });
    });

    test('each tested city uses its customary method and Asr school by default', () {
      const expected = <String, (String, int)>{
        'makkah': ('makkah', 1),
        'cairo': ('egypt', 1),
        'dubai': ('dubai', 1),
        'abudhabi': ('dubai', 1),
        'kuwait': ('kuwait', 1),
        'doha': ('qatar', 1),
        'karachi': ('karachi', 2),
        'istanbul': ('turkey', 1),
        'jakarta': ('kemenag', 1),
        'kl': ('jakim', 1),
        'casa': ('morocco', 1),
        'algiers': ('algeria', 1),
        'tunis': ('tunisia', 1),
        'amman': ('jordan', 1),
        'london': ('mwl', 1),
        'paris': ('france', 1),
        'berlin': ('mwl', 1),
        'nyc': ('isna', 1),
        'toronto': ('isna', 1),
        'la': ('isna', 1),
        'sydney': ('mwl', 1),
        'lagos': ('mwl', 1),
      };
      expected.forEach((cityId, e) {
        final c = WorldCase.catalog(cityId);
        expect((c.methodId, c.asrFactor), e, reason: cityId);
      });
    });

    test('every catalog city has a time zone known to the bundled database', () {
      for (final city in cities) {
        expect(() => tz.getLocation(city.timeZone), returnsNormally, reason: city.id);
      }
    });

    test('Umm al-Qura: Isha is Maghrib + 90 min, also in Ramadan (no Ramadan rule yet)', () {
      final makkah = WorldCase.catalog('makkah');
      // ~15 Ramadan 1448 (approximate date, only used to pick a day inside the month).
      final raw = appUtcMinutes(makkah, DateTime.utc(2027, 2, 22));
      expect(raw[Prayer.isha.index] - raw[Prayer.maghrib.index], closeTo(90, 1e-6));
    });

    test(
      'Umm al-Qura: Isha is Maghrib + 120 min during Ramadan',
      () {
        final makkah = WorldCase.catalog('makkah');
        // 2027-02-22 is well inside Ramadan 1448 whichever day the month starts (about
        // 8-9 Feb 2027); 2027-05-01 is well outside it. The app must get "is it Ramadan"
        // from a verified Umm al-Qura source, not from these dates.
        final ramadan = appUtcMinutes(makkah, DateTime.utc(2027, 2, 22));
        expect(ramadan[Prayer.isha.index] - ramadan[Prayer.maghrib.index], closeTo(120, 1e-6));
        final normal = appUtcMinutes(makkah, DateTime.utc(2027, 5, 1));
        expect(normal[Prayer.isha.index] - normal[Prayer.maghrib.index], closeTo(90, 1e-6));
      },
      skip: 'TODO(scholar + owner): the Umm al-Qura calendar uses Isha = Maghrib + 120 min in '
          'Ramadan (adhan: "UmmAlQura ... 30 minutes in Ramadan"). The app has no Hijri '
          'calendar, so this cannot be applied yet. Needs a decision and a verified, offline Umm al-Qura '
          'month-start source (none is vetted in the project yet; Saudi Ramadan is also announced by '
          'sighting, which can differ from the calendar by a day). Enable when that source lands.',
    );
  });
}
