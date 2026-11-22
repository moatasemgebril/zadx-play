import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/app_variant.dart';
import '../../data/catalog/locations.dart';
import '../settings/settings_controller.dart';
import 'prayer_calculator.dart';

/// Emits once a minute so "next prayer" and locks stay current.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

/// Wall-clock "now" in the selected city's time zone.
class CityNow {
  const CityNow(this.local, this.utcOffsetHours);
  final DateTime local;
  final double utcOffsetHours;
  double get hours => local.hour + local.minute / 60;
}

/// Zad X Kids has no city setting (no prayer times): "now" is the device's local time, which is
/// also what its schedules and the native blockers use.
final cityNowProvider = Provider<CityNow>((ref) {
  ref.watch(clockProvider);
  if (kIsKids) {
    final now = DateTime.now();
    return CityNow(DateTime(now.year, now.month, now.day, now.hour, now.minute), now.timeZoneOffset.inMinutes / 60);
  }
  final city = cityById(ref.watch(settingsProvider.select((s) => s.cityId)));
  final now = tz.TZDateTime.now(tz.getLocation(city.timeZone));
  return CityNow(
    DateTime(now.year, now.month, now.day, now.hour, now.minute),
    now.timeZoneOffset.inMinutes / 60,
  );
});

final prayerTimesProvider = Provider<PrayerTimes>((ref) {
  final s = ref.watch(settingsProvider);
  final city = cityById(s.cityId);
  final now = ref.watch(cityNowProvider);
  return const PrayerCalculator().compute(
    date: now.local,
    lat: city.lat,
    lng: city.lng,
    utcOffsetHours: now.utcOffsetHours,
    method: methodById(s.methodId),
    asrFactor: s.asrFactor,
  );
});

final nextPrayerProvider = Provider<Prayer>((ref) {
  return ref.watch(prayerTimesProvider).nextAfter(ref.watch(cityNowProvider).hours);
});
