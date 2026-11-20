import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/locations.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';

/// Reference values computed with the same algorithm as the approved prototype
/// and cross-checked against published timetables (±2 minutes).
void main() {
  const calc = PrayerCalculator();

  double minutes(double h) => h * 60;

  test('Cairo, Egyptian Authority, 20 Nov 2026', () {
    final cairo = cityById('cairo');
    final t = calc.compute(
      date: DateTime(2026, 11, 20),
      lat: cairo.lat,
      lng: cairo.lng,
      utcOffsetHours: 2,
      method: methodById('egypt'),
    );
    expect(minutes(t.of(Prayer.fajr)), closeTo(4 * 60 + 54, 2));
    expect(minutes(t.of(Prayer.dhuhr)), closeTo(11 * 60 + 42, 2));
    expect(minutes(t.of(Prayer.asr)), closeTo(14 * 60 + 37, 2));
    expect(minutes(t.of(Prayer.maghrib)), closeTo(16 * 60 + 57, 2));
    expect(minutes(t.of(Prayer.isha)), closeTo(18 * 60 + 18, 2));
  });

  test('Umm al-Qura: Isha is 90 minutes after Maghrib', () {
    final makkah = cityById('makkah');
    final t = calc.compute(
      date: DateTime(2026, 11, 20),
      lat: makkah.lat,
      lng: makkah.lng,
      utcOffsetHours: 3,
      method: methodById('makkah'),
    );
    expect(minutes(t.of(Prayer.isha) - t.of(Prayer.maghrib)), closeTo(90, 0.01));
  });

  test('Hanafi Asr is later than standard Asr', () {
    final karachi = cityById('karachi');
    PrayerTimes run(int factor) => calc.compute(
          date: DateTime(2026, 11, 20),
          lat: karachi.lat,
          lng: karachi.lng,
          utcOffsetHours: 5,
          method: methodById('karachi'),
          asrFactor: factor,
        );
    expect(run(2).of(Prayer.asr), greaterThan(run(1).of(Prayer.asr)));
  });

  test('prayers are in chronological order for every city', () {
    for (final city in cities) {
      final country = countryById(city.countryId);
      final t = calc.compute(
        date: DateTime(2026, 3, 15),
        lat: city.lat,
        lng: city.lng,
        utcOffsetHours: 0,
        method: methodById(country.methodId),
        asrFactor: country.asrFactor,
      );
      final h = Prayer.values.map(t.of).toList();
      for (var i = 1; i < h.length; i++) {
        expect(h[i], greaterThan(h[i - 1]), reason: '${city.id} ${Prayer.values[i]}');
      }
    }
  });

  test('nextAfter wraps to Fajr after Isha', () {
    const t = PrayerTimes([5, 12, 15, 17, 18.5]);
    expect(t.nextAfter(4), Prayer.fajr);
    expect(t.nextAfter(13), Prayer.asr);
    expect(t.nextAfter(23), Prayer.fajr);
  });

  test('play windows sit between prayers', () {
    const t = PrayerTimes([5, 12, 15, 17, 18.5]);
    final w = playWindows(t);
    expect(w.length, 3);
    expect(w.first.start, closeTo(12 + 20 / 60, 1e-9));
    expect(w.first.end, closeTo(15 - 10 / 60, 1e-9));
  });

  test('catalog integrity: unique city ids and every country has a city', () {
    final ids = cities.map((c) => c.id).toSet();
    expect(ids.length, cities.length);
    for (final c in countries) {
      expect(citiesOf(c.id), isNotEmpty, reason: c.id);
      expect(calcMethods.containsKey(c.methodId), isTrue, reason: c.id);
    }
  });
}
