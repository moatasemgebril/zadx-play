import 'dart:math' as math;

import '../../data/models/location.dart';
import 'hijri_ramadan.dart';

enum Prayer { fajr, dhuhr, asr, maghrib, isha }

/// How Fajr and Isha are found when the twilight angle is reached late or never
/// (high latitudes in summer).
///
/// [relativeEstimation45] and [angle12] follow the European Council for Fatwa and Research
/// (ECFR resolution 41 (2/12)) and the MWL Fiqh Academy: they apply only on days when the
/// sign (the method's twilight angle) is absent, so a real Fajr/Isha is never replaced.
///
/// The night-portion rules are the definitions of the adhan library (batoulapps
/// `HighLatitudeRule`) and PrayTimes.org: the night (sunset to next sunrise) is cut into
/// portions; Fajr is never earlier than `sunrise - portion * night` and Isha never later
/// than `sunset + portion * night`.
///
/// Decision record: docs/decisions/PRAYER-TIMES-ACCURACY.md.
enum HighLatitudeRule {
  /// Relative estimation from latitude 45° (same hemisphere, longitude and date, same method
  /// angles): on a day without the sign, Isha = sunset + f_isha × night and Fajr = sunrise −
  /// f_fajr × night, where f = (Maghrib→Isha) / night and (Fajr→sunrise) / night at 45°.
  relativeEstimation45,

  /// 12° below the horizon for Fajr and Isha on days the method's angle is not reached (ECFR
  /// permits it). Where even 12° is not reached (e.g. Oslo in June), [relativeEstimation45].
  angle12,

  /// Fajr and Isha portions are 1/2 of the night.
  middleOfTheNight,

  /// Fajr and Isha portions are 1/7 of the night.
  seventhOfTheNight,

  /// Portions are angle / 60 (e.g. 18° gives 18/60 of the night).
  twilightAngle,
}

/// The parent's choice in Settings. [auto] = [HighLatitudeRule.relativeEstimation45] at
/// latitudes of 48° and above (where Fajr/Isha can disappear in summer), no rule below.
enum HighLatitudeSetting {
  auto,
  relativeEstimation45,
  angle12,
  middleOfTheNight,
  seventhOfTheNight,
  twilightAngle;

  static HighLatitudeSetting parse(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => auto);
}

/// Latitude from which [HighLatitudeSetting.auto] applies a rule.
const highLatitudeAutoFromDegrees = 48.0;

/// The rule to compute with for [setting] at [lat] (`null` = no rule).
HighLatitudeRule? resolveHighLatitudeRule(HighLatitudeSetting setting, double lat) => switch (setting) {
      HighLatitudeSetting.auto => lat.abs() >= highLatitudeAutoFromDegrees ? HighLatitudeRule.relativeEstimation45 : null,
      HighLatitudeSetting.relativeEstimation45 => HighLatitudeRule.relativeEstimation45,
      HighLatitudeSetting.angle12 => HighLatitudeRule.angle12,
      HighLatitudeSetting.middleOfTheNight => HighLatitudeRule.middleOfTheNight,
      HighLatitudeSetting.seventhOfTheNight => HighLatitudeRule.seventhOfTheNight,
      HighLatitudeSetting.twilightAngle => HighLatitudeRule.twilightAngle,
    };

/// Prayer times for one day, as local clock hours (e.g. 15.42 = 15:25).
class PrayerTimes {
  const PrayerTimes(this.hours);

  /// Indexed by [Prayer.index]. A value may be NaN at extreme latitudes.
  final List<double> hours;

  double of(Prayer p) => hours[p.index];

  /// The next prayer after [nowHours]; wraps to Fajr after Isha.
  Prayer nextAfter(double nowHours) {
    for (final p in Prayer.values) {
      final h = of(p);
      if (h.isFinite && h > nowHours) return p;
    }
    return Prayer.fajr;
  }

  /// Converts a prayer to a DateTime on [date] in the city's local wall clock.
  DateTime toLocalDateTime(Prayer p, DateTime date) {
    final h = of(p);
    final minutes = (h * 60).round();
    return DateTime(date.year, date.month, date.day).add(Duration(minutes: minutes));
  }
}

/// Astronomical prayer-time calculator (same algorithm as the approved prototype,
/// based on the widely used PrayTimes.org formulas).
///
/// Pure and deterministic, so it is unit-tested in `test/prayer_calculator_test.dart`.
class PrayerCalculator {
  const PrayerCalculator();

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;
  static double _fixAngle(double a) => (a % 360 + 360) % 360;

  /// [utcOffsetHours] is the city's offset on [date] (DST aware), e.g. 2 for Cairo.
  ///
  /// [highLatitudeRule] (see [HighLatitudeRule]) fills in Fajr and Isha when the sun never
  /// reaches the twilight angle (and, for the night-portion rules, bounds them). `null` = no
  /// rule (Fajr/Isha are NaN when the angle is not reached). A fixed-interval Isha
  /// (Umm al-Qura, Qatar) is never changed by the rule, as in the adhan library.
  ///
  /// [date]'s year/month/day is the city's calendar day. With Umm al-Qura, Isha is
  /// Maghrib + 120 min on days of Ramadan in the Umm al-Qura calendar, shifted by the
  /// parent's [hijriAdjustmentDays] (-1, 0, +1); see `hijri_ramadan.dart`.
  PrayerTimes compute({
    required DateTime date,
    required double lat,
    required double lng,
    required double utcOffsetHours,
    required CalcMethod method,
    int asrFactor = 1,
    HighLatitudeRule? highLatitudeRule,
    int hijriAdjustmentDays = 0,
  }) {
    final utcMidnight = DateTime.utc(date.year, date.month, date.day);
    final jd = utcMidnight.millisecondsSinceEpoch / 86400000 + 2440587.5 + 0.5 - lng / 360;
    final sun = _sunPosition(jd);
    final noon = 12 - sun.eqt;

    double angleTime(double angle, {required bool beforeNoon}) => _angleTime(sun, angle, lat, beforeNoon: beforeNoon);

    var fajr = angleTime(method.fajrAngle, beforeNoon: true);
    final dhuhr = noon + 1 / 60; // 1 minute after zenith
    final asrAngle = -_deg(math.atan(1 / (asrFactor + math.tan(_rad((lat - sun.decl).abs())))));
    final asr = angleTime(asrAngle, beforeNoon: false);
    final maghrib = angleTime(0.833, beforeNoon: false);
    final ishaInterval =
        ishaIntervalOn(method, date.year, date.month, date.day, hijriAdjustmentDays: hijriAdjustmentDays);
    var isha = ishaInterval != null ? maghrib + ishaInterval / 60 : angleTime(method.ishaAngle!, beforeNoon: false);

    if (highLatitudeRule != null) {
      final sunrise = angleTime(0.833, beforeNoon: true);
      // Next morning's sunrise, from the sun's position one day later (adhan: tomorrow's sunrise).
      final nextSun = _sunPosition(jd + 1);
      final nextSunrise = 24 + _angleTime(nextSun, 0.833, lat, beforeNoon: true);
      final night = nextSunrise - maghrib;
      final angleIsha = method.ishaMinutesAfterMaghrib == null;
      if (sunrise.isFinite && night.isFinite && night > 0) {
        switch (highLatitudeRule) {
          case HighLatitudeRule.relativeEstimation45:
          case HighLatitudeRule.angle12:
            // Only on a day without the sign (ECFR): a real Fajr/Isha is never replaced.
            final f = _fractionsAt(lat < 0 ? -45.0 : 45.0, sun, nextSun, method);
            if (fajr.isNaN) {
              if (highLatitudeRule == HighLatitudeRule.angle12) fajr = angleTime(12, beforeNoon: true);
              if (fajr.isNaN) fajr = sunrise - f.fajr * night;
            }
            if (angleIsha && isha.isNaN) {
              if (highLatitudeRule == HighLatitudeRule.angle12) isha = angleTime(12, beforeNoon: false);
              if (isha.isNaN) isha = maghrib + f.isha * night;
            }
          case HighLatitudeRule.middleOfTheNight:
          case HighLatitudeRule.seventhOfTheNight:
          case HighLatitudeRule.twilightAngle:
            final (fajrPortion, ishaPortion) = switch (highLatitudeRule) {
              HighLatitudeRule.middleOfTheNight => (1 / 2, 1 / 2),
              HighLatitudeRule.seventhOfTheNight => (1 / 7, 1 / 7),
              _ => (method.fajrAngle / 60, (method.ishaAngle ?? 0) / 60),
            };
            final safeFajr = sunrise - fajrPortion * night;
            if (fajr.isNaN || safeFajr > fajr) fajr = safeFajr;
            if (angleIsha) {
              final safeIsha = maghrib + ishaPortion * night;
              if (isha.isNaN || safeIsha < isha) isha = safeIsha;
            }
        }
      }
    }

    final adjust = utcOffsetHours - lng / 15;
    return PrayerTimes([fajr, dhuhr, asr, maghrib, isha].map((t) => t + adjust).toList());
  }

  /// Local hour (at longitude 0) when the sun is [angle]° below the horizon at [lat];
  /// NaN when it never gets there that day.
  static double _angleTime(({double decl, double eqt}) s, double angle, double lat, {required bool beforeNoon}) {
    final x = (-math.sin(_rad(angle)) - math.sin(_rad(s.decl)) * math.sin(_rad(lat))) /
        (math.cos(_rad(s.decl)) * math.cos(_rad(lat)));
    if (x < -1 || x > 1) return double.nan; // sun never reaches that angle
    final t = _deg(math.acos(x)) / 15;
    return 12 - s.eqt + (beforeNoon ? -t : t);
  }

  /// Relative estimation: at [refLat] (±45°) on the same date, the share of the night
  /// (sunset to next sunrise) from Fajr to sunrise and from sunset (Maghrib) to Isha.
  /// The longitude only shifts all times equally, so it does not change the shares.
  static ({double fajr, double isha}) _fractionsAt(
    double refLat,
    ({double decl, double eqt}) sun,
    ({double decl, double eqt}) nextSun,
    CalcMethod method,
  ) {
    final maghrib = _angleTime(sun, 0.833, refLat, beforeNoon: false);
    final sunrise = _angleTime(sun, 0.833, refLat, beforeNoon: true);
    final night = 24 + _angleTime(nextSun, 0.833, refLat, beforeNoon: true) - maghrib;
    final fajr = _angleTime(sun, method.fajrAngle, refLat, beforeNoon: true);
    final isha = method.ishaAngle == null ? double.nan : _angleTime(sun, method.ishaAngle!, refLat, beforeNoon: false);
    return (fajr: (sunrise - fajr) / night, isha: (isha - maghrib) / night);
  }

  static ({double decl, double eqt}) _sunPosition(double jd) {
    final d = jd - 2451545.0;
    final g = _fixAngle(357.529 + 0.98560028 * d);
    final q = _fixAngle(280.459 + 0.98564736 * d);
    final l = _fixAngle(q + 1.915 * math.sin(_rad(g)) + 0.020 * math.sin(_rad(2 * g)));
    final e = 23.439 - 0.00000036 * d;
    var ra = _deg(math.atan2(math.cos(_rad(e)) * math.sin(_rad(l)), math.cos(_rad(l)))) / 15;
    ra = (ra % 24 + 24) % 24;
    var eqt = q / 15 - ra;
    eqt = ((eqt + 12) % 24 + 24) % 24 - 12;
    final decl = _deg(math.asin(math.sin(_rad(e)) * math.sin(_rad(l))));
    return (decl: decl, eqt: eqt);
  }
}

/// Suggested play windows between prayers (used for the PlayStation schedule).
List<({Prayer after, double start, double end})> playWindows(
  PrayerTimes t, {
  int afterMinutes = 20,
  int beforeMinutes = 10,
}) {
  final pairs = [
    (Prayer.dhuhr, Prayer.asr),
    (Prayer.asr, Prayer.maghrib),
    (Prayer.maghrib, Prayer.isha),
  ];
  return [
    for (final (a, b) in pairs)
      if (t.of(a).isFinite && t.of(b).isFinite)
        (after: a, start: t.of(a) + afterMinutes / 60, end: t.of(b) - beforeMinutes / 60),
  ].where((w) => w.end - w.start >= 0.25).toList();
}
