import 'package:timezone/timezone.dart' as tz;

import '../../data/models/location.dart';

/// The time zone to show a city's prayer times in.
///
/// Normally the city's IANA zone from the bundled database (package:timezone). One known
/// exception is corrected here because the bundled database is older than the law:
///
/// * Morocco (Africa/Casablanca, Africa/El_Aaiun): IANA tzdata 2026c (released
///   2026-07-08, https://www.iana.org/time-zones/releases/2026c) says "Morocco plans to
///   move back to permanent UTC, without daylight saving time transitions, on 2026-09-20
///   at 02:00." timezone 0.10.1 (the newest allowed by flutter_local_notifications 18)
///   still has +01, so every Moroccan time would show one hour late. While the bundled
///   data is stale (still not +00 after the switch), these zones are replaced by UTC.
///   Once a newer timezone package ships 2026c+ data, the real zone is used again
///   automatically (the check below then finds +00).
///
/// Only the zone used on screen and for scheduling changes; the IANA name synced to other
/// devices (Windows Guard, backend) stays the real one, they use their own up-to-date data.
tz.Location cityLocation(City city) => locationForZone(city.timeZone);

/// See [cityLocation].
tz.Location locationForZone(String name) {
  final location = tz.getLocation(name);
  if (_moroccanZones.contains(name)) {
    final probe = tz.TZDateTime.from(_moroccoPermanentUtcCheck, location);
    if (probe.timeZoneOffset != Duration.zero) return tz.UTC;
  }
  return location;
}

const _moroccanZones = {'Africa/Casablanca', 'Africa/El_Aaiun'};

/// A moment after Morocco's switch to permanent UTC (2026-09-20 02:00) and outside any
/// Ramadan, so an up-to-date database gives +00 and a stale one gives +01.
final _moroccoPermanentUtcCheck = DateTime.utc(2026, 11, 1, 12);
