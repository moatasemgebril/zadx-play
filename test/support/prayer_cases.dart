import 'package:zadx/core/localized.dart';
import 'package:zadx/data/catalog/locations.dart';
import 'package:zadx/data/models/location.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';

import 'solar_reference.dart';

/// One city with the method and Asr rule it is tested with.
class WorldCase {
  const WorldCase(this.city, this.methodId, {this.asrFactor = 1, this.inCatalog = true});

  /// A city from the app's catalog, with its country's default method and Asr rule.
  factory WorldCase.catalog(String cityId) {
    final city = cityById(cityId);
    if (city.id != cityId) throw ArgumentError('city "$cityId" is not in lib/data/catalog/locations.dart');
    final country = countryById(city.countryId);
    return WorldCase(city, country.methodId, asrFactor: country.asrFactor);
  }

  final City city;
  final String methodId;
  final int asrFactor;

  /// False for cities that users cannot pick yet (tested straight on the calculator).
  final bool inCatalog;

  CalcMethod get method => methodById(methodId);

  /// Allowed difference from the reference, in minutes.
  ///
  /// * below 48°: ±2 min (requested tolerance; the observed worst case is < 1 min);
  /// * 48°–56° (London, Paris, Berlin): ±3 min;
  /// * 56° and above (Stockholm, Oslo, Reykjavik): ±5 min.
  /// The further from the equator, the more slowly the sun crosses the horizon and
  /// the twilight angles, so the same small difference in the sun's position (the app
  /// uses one noon position for the whole day, the reference solves each event at its
  /// own time) becomes more minutes.
  double get toleranceMinutes {
    final a = city.lat.abs();
    if (a < 48) return 2;
    if (a < 56) return 3;
    return 5;
  }

  @override
  String toString() => '${city.name.en} [$methodId, asr x$asrFactor]';
}

/// Cities that are not in the app's picker yet, tested on the calculator directly.
const stockholm = City(
  id: 'test-stockholm',
  countryId: '',
  name: Localized('ستوكهولم', 'Stockholm'),
  lat: 59.3293,
  lng: 18.0686,
  timeZone: 'Europe/Stockholm',
);
const oslo = City(
  id: 'test-oslo',
  countryId: '',
  name: Localized('أوسلو', 'Oslo'),
  lat: 59.9139,
  lng: 10.7522,
  timeZone: 'Europe/Oslo',
);
const reykjavik = City(
  id: 'test-reykjavik',
  countryId: '',
  name: Localized('ريكيافيك', 'Reykjavik'),
  lat: 64.1466,
  lng: -21.9426,
  timeZone: 'Atlantic/Reykjavik',
);
const johannesburg = City(
  id: 'test-johannesburg',
  countryId: '',
  name: Localized('جوهانسبرغ', 'Johannesburg'),
  lat: -26.2041,
  lng: 28.0473,
  timeZone: 'Africa/Johannesburg',
);

/// The world tour requested by the owner (2026-11-22), with each city's customary method.
final List<WorldCase> worldCases = [
  WorldCase.catalog('makkah'), // Umm al-Qura
  WorldCase.catalog('cairo'), // Egyptian General Authority of Survey
  WorldCase.catalog('dubai'),
  WorldCase.catalog('abudhabi'),
  WorldCase.catalog('kuwait'),
  WorldCase.catalog('doha'), // Qatar (Isha = Maghrib + 90)
  WorldCase.catalog('karachi'), // Univ. of Karachi + Hanafi Asr (country default)
  WorldCase.catalog('istanbul'), // "Diyanet" angles 18/17
  WorldCase.catalog('jakarta'), // Kemenag 20/18
  WorldCase.catalog('kl'), // JAKIM 20/18
  WorldCase.catalog('casa'), // Morocco 19/17
  WorldCase.catalog('algiers'),
  WorldCase.catalog('tunis'),
  WorldCase.catalog('amman'),
  WorldCase.catalog('london'), // MWL
  WorldCase.catalog('paris'), // UOIF 12/12
  WorldCase.catalog('berlin'), // MWL
  WorldCase.catalog('nyc'), // ISNA
  WorldCase.catalog('toronto'), // ISNA
  WorldCase.catalog('la'), // ISNA
  WorldCase.catalog('sydney'), // MWL (southern hemisphere)
  WorldCase.catalog('lagos'), // MWL
  const WorldCase(johannesburg, 'mwl', inCatalog: false),
  const WorldCase(stockholm, 'mwl', inCatalog: false),
  const WorldCase(oslo, 'mwl', inCatalog: false),
  const WorldCase(reykjavik, 'mwl', inCatalog: false),
];

/// Dates: the 1st and 15th of every month of 2026, plus equinoxes, solstices, the year
/// boundary, the leap day 2028-02-29 and (approximately) the start and end of Ramadan
/// 1448 AH in 2027.
final List<DateTime> worldDates = [
  for (var m = 1; m <= 12; m++) DateTime.utc(2026, m, 1),
  for (var m = 1; m <= 12; m++) DateTime.utc(2026, m, 15),
  DateTime.utc(2026, 3, 20), // March equinox
  DateTime.utc(2026, 6, 21), // June solstice
  DateTime.utc(2026, 9, 23), // September equinox
  DateTime.utc(2026, 12, 21), // December solstice
  DateTime.utc(2026, 12, 31),
  DateTime.utc(2027, 1, 1),
  DateTime.utc(2027, 2, 8), // ~1 Ramadan 1448 (approximate, not a religious ruling)
  DateTime.utc(2027, 3, 9), // ~end of Ramadan 1448 (approximate)
  DateTime.utc(2027, 6, 21),
  DateTime.utc(2027, 12, 22),
  DateTime.utc(2028, 2, 29), // leap day
  DateTime.utc(2028, 3, 1),
];

/// App result in minutes after 00:00 UTC of [date] (NaN when the angle is not reached).
List<double> appUtcMinutes(WorldCase c, DateTime date, {int? asrFactor}) {
  final t = const PrayerCalculator().compute(
    date: DateTime.utc(date.year, date.month, date.day),
    lat: c.city.lat,
    lng: c.city.lng,
    utcOffsetHours: 0,
    method: c.method,
    asrFactor: asrFactor ?? c.asrFactor,
  );
  return [for (final p in Prayer.values) t.of(p) * 60];
}

RefDay referenceFor(WorldCase c, DateTime date, {int? asrFactor}) => SolarReference.day(
      year: date.year,
      month: date.month,
      day: date.day,
      lat: c.city.lat,
      lng: c.city.lng,
      fajrAngle: c.method.fajrAngle,
      ishaAngle: c.method.ishaAngle,
      ishaMinutesAfterMaghrib: c.method.ishaMinutesAfterMaghrib,
      asrFactor: asrFactor ?? c.asrFactor,
    );
