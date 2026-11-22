import '../../core/localized.dart';

/// Prayer-time calculation convention (twilight angles).
class CalcMethod {
  const CalcMethod({
    required this.id,
    required this.name,
    required this.fajrAngle,
    this.ishaAngle,
    this.ishaMinutesAfterMaghrib,
    this.ishaMinutesAfterMaghribInRamadan,
  }) : assert(ishaAngle != null || ishaMinutesAfterMaghrib != null),
       assert(ishaMinutesAfterMaghribInRamadan == null || ishaMinutesAfterMaghrib != null);

  final String id;
  final Localized name;
  final double fajrAngle;
  final double? ishaAngle;

  /// Used by Umm al-Qura / Qatar: Isha is a fixed interval after Maghrib.
  final int? ishaMinutesAfterMaghrib;

  /// Umm al-Qura only: Isha interval during Ramadan of the Umm al-Qura Hijri calendar
  /// (120 min, Saudi Press Agency https://www.spa.gov.sa/907467). See
  /// `lib/features/prayer/hijri_ramadan.dart`.
  final int? ishaMinutesAfterMaghribInRamadan;
}

class Country {
  const Country({
    required this.id,
    required this.name,
    required this.methodId,
    this.asrFactor = 1,
  });

  final String id;
  final Localized name;
  final String methodId;

  /// 1 = standard (Shafi, Maliki, Hanbali), 2 = Hanafi.
  final int asrFactor;
}

class City {
  const City({
    required this.id,
    required this.countryId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.timeZone,
  });

  final String id;
  final String countryId;
  final Localized name;
  final double lat;
  final double lng;

  /// IANA zone, e.g. "Africa/Cairo".
  final String timeZone;
}
