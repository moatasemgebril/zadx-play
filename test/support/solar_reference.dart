import 'dart:math' as math;

/// An independent reference for prayer times, used only by the tests.
///
/// Source: the NOAA Solar Calculator spreadsheet formulas (NOAA Global Monitoring
/// Laboratory, "General Solar Position Calculations", which are based on Jean Meeus,
/// *Astronomical Algorithms*, 2nd ed., ch. 25 and 28).
///
/// It is deliberately different from the app's `PrayerCalculator` (PrayTimes.org
/// short formulas, one sun position at local noon):
/// * Meeus/NOAA series for the sun's longitude, nutation-corrected obliquity and the
///   equation of time (instead of the shorter PrayTimes.org series), and
/// * each event is solved iteratively with the sun's position *at that event's own
///   time* (instead of the sun's position at noon for the whole day).
///
/// The Islamic definitions are the standard ones used by every calculator
/// (PrayTimes.org, adhan, Umm al-Qura, Egyptian Authority, ISNA, MWL ...):
/// * Fajr / Isha: the sun's centre is the method's angle below the horizon;
/// * Sunrise / Maghrib: the sun's upper limb on the horizon (centre at -0.833°,
///   refraction 34' + semi-diameter 16');
/// * Dhuhr: solar transit (the app adds +1 minute, see [RefDay.transit]);
/// * Asr: shadow length = asrFactor × object + noon shadow
///   (1 = Shafi'i/Maliki/Hanbali, 2 = Hanafi).
///
/// All results are minutes after 00:00 **UTC** of the given calendar date (they may be
/// negative or above 1440 for cities far from Greenwich). `null` means the sun never
/// reaches that angle on that day.
class SolarReference {
  const SolarReference._();

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;

  /// Julian day of 00:00 UTC on the date.
  static double _jd0(int year, int month, int day) =>
      DateTime.utc(year, month, day).millisecondsSinceEpoch / 86400000 + 2440587.5;

  /// Sun declination (degrees) and equation of time (minutes) at Julian day [jd].
  static ({double decl, double eotMinutes}) sun(double jd) {
    final t = (jd - 2451545.0) / 36525; // Julian centuries since J2000.0
    final l0 = (280.46646 + t * (36000.76983 + 0.0003032 * t)) % 360;
    final m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    final ecc = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    final c = math.sin(_rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        math.sin(_rad(2 * m)) * (0.019993 - 0.000101 * t) +
        math.sin(_rad(3 * m)) * 0.000289;
    final trueLong = l0 + c;
    final omega = 125.04 - 1934.136 * t;
    final apparentLong = trueLong - 0.00569 - 0.00478 * math.sin(_rad(omega));
    final meanObliq = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
    final obliq = meanObliq + 0.00256 * math.cos(_rad(omega));
    final decl = _deg(math.asin(math.sin(_rad(obliq)) * math.sin(_rad(apparentLong))));
    final y = math.pow(math.tan(_rad(obliq / 2)), 2).toDouble();
    final eot = 4 *
        _deg(y * math.sin(2 * _rad(l0)) -
            2 * ecc * math.sin(_rad(m)) +
            4 * ecc * y * math.sin(_rad(m)) * math.cos(2 * _rad(l0)) -
            0.5 * y * y * math.sin(4 * _rad(l0)) -
            1.25 * ecc * ecc * math.sin(2 * _rad(m)));
    return (decl: decl, eotMinutes: eot);
  }

  /// How many degrees the sun goes *below* [angle] at its lowest point of the night
  /// (local midnight). Negative: the sun never gets that low, so the angle-based time
  /// does not exist. Values near 0 mean the time is extremely sensitive (it moves by
  /// many minutes for a tiny change in the sun's position).
  static double twilightMargin({
    required int year,
    required int month,
    required int day,
    required double lat,
    required double lng,
    required double angle,
  }) {
    final decl = sun(_jd0(year, month, day) + 0.5 - lng / 360).decl;
    final lowest = _deg(math.asin(math.sin(_rad(lat)) * math.sin(_rad(decl)) -
        math.cos(_rad(lat)) * math.cos(_rad(decl))));
    return -lowest - angle;
  }

  static RefDay day({
    required int year,
    required int month,
    required int day,
    required double lat,
    required double lng,
    required double fajrAngle,
    double? ishaAngle,
    int? ishaMinutesAfterMaghrib,
    int asrFactor = 1,
  }) {
    final jd0 = _jd0(year, month, day);

    double noonAt(double minutesUtc) => 720 - 4 * lng - sun(jd0 + minutesUtc / 1440).eotMinutes;

    var transit = 720 - 4 * lng;
    for (var i = 0; i < 3; i++) {
      transit = noonAt(transit);
    }

    /// Solves "sun altitude == altitude(decl)" before or after transit.
    double? event(double Function(double decl) altitude, {required bool beforeNoon}) {
      var t = transit + (beforeNoon ? -360 : 360);
      for (var i = 0; i < 8; i++) {
        final s = sun(jd0 + t / 1440);
        final alt = altitude(s.decl);
        final x = (math.sin(_rad(alt)) - math.sin(_rad(lat)) * math.sin(_rad(s.decl))) /
            (math.cos(_rad(lat)) * math.cos(_rad(s.decl)));
        if (x < -1 || x > 1) return null;
        final hourAngleMinutes = _deg(math.acos(x)) * 4;
        final noon = 720 - 4 * lng - s.eotMinutes;
        t = beforeNoon ? noon - hourAngleMinutes : noon + hourAngleMinutes;
      }
      return t;
    }

    final fajr = event((_) => -fajrAngle, beforeNoon: true);
    final sunrise = event((_) => -0.833, beforeNoon: true);
    final asr = event(
      (decl) => _deg(math.atan(1 / (asrFactor + math.tan(_rad((lat - decl).abs()))))),
      beforeNoon: false,
    );
    final maghrib = event((_) => -0.833, beforeNoon: false);
    final double? isha;
    if (ishaMinutesAfterMaghrib != null) {
      isha = maghrib == null ? null : maghrib + ishaMinutesAfterMaghrib;
    } else {
      isha = event((_) => -ishaAngle!, beforeNoon: false);
    }
    return RefDay(fajr: fajr, sunrise: sunrise, transit: transit, asr: asr, maghrib: maghrib, isha: isha);
  }
}

/// Reference times in minutes after 00:00 UTC of the date.
class RefDay {
  const RefDay({
    required this.fajr,
    required this.sunrise,
    required this.transit,
    required this.asr,
    required this.maghrib,
    required this.isha,
  });

  final double? fajr;
  final double? sunrise;

  /// Solar noon. The app's Dhuhr is transit + 1 minute (a common safety margin,
  /// PrayTimes.org "dhuhr: 1 min" setting), so tests compare Dhuhr with transit + 1.
  final double transit;
  final double? asr;
  final double? maghrib;
  final double? isha;
}
