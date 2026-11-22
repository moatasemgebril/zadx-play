# Prayer times: accuracy decisions and open items

Status: engineering notes, 2026-11-22. Items marked **pending scholar review** need the
Islamic Content Reviewer and the owner before release. Nothing here invents religious
rulings or official timetable numbers.

## 1. High-latitude rule (pending scholar review)

Far from the equator the sun does not go 17-18° below the horizon on summer nights, so
angle-based Fajr and Isha do not exist (London: about 21 May to 23 July for 18°). Without a
rule there is no Fajr/Isha time, no adhan and no prayer lock for those weeks.

The app now has a parent setting (Settings > "High-latitude rule", marked "Pending scholar
review / بانتظار مراجعة الشيخ") with the standard definitions of the adhan library
(batoulapps `HighLatitudeRule`) and PrayTimes.org. The night is sunset to the next sunrise:

| Option | Fajr is never earlier than | Isha is never later than |
|---|---|---|
| Middle of the night | sunrise - 1/2 night | sunset + 1/2 night |
| One-seventh of the night | sunrise - 1/7 night | sunset + 1/7 night |
| Twilight angle | sunrise - (Fajr angle / 60) night | sunset + (Isha angle / 60) night |

* Default ("Automatic"): Twilight angle at latitudes of 48° and above, no rule below 48°.
* A fixed-interval Isha (Umm al-Qura, Qatar: Maghrib + 90 min) is never moved by the rule.
* With "Middle of the night", Isha and the next Fajr meet at midnight; the adhan plan then
  keeps only one adhan for that minute (no double adhan / double lock). Scholar question:
  which of the two should it be named?
* Wired into: displayed times (`prayerTimesProvider`), adhan notifications
  (`planAdhanNotifications`), the phone prayer lock (`app_lock_service`), and Windows Guard
  (synced as `settings.highLatRule`, passed by the `devicePolicy` function; an older app that
  does not sync it gets the same default on the guard).

Code: `lib/features/prayer/prayer_calculator.dart`, `windows_guard/PrayerTimes.cs`.
Tests: `test/prayer_times_world_test.dart` group "high latitudes".

## 2. Morocco time zone (fixed)

IANA tzdata 2026c (released 2026-07-08, https://www.iana.org/time-zones/releases/2026c):
"Morocco plans to move back to permanent UTC, without daylight saving time transitions, on
2026-09-20 at 02:00." The bundled `timezone` 0.10.1 (newest allowed by
flutter_local_notifications 18) predates it. `lib/features/prayer/city_time_zone.dart` uses
UTC for Africa/Casablanca and Africa/El_Aaiun while the bundled data is stale, and switches
itself off when a newer database has +00. Remove it after the planned
flutter_local_notifications / timezone upgrade.

## 3. Umm al-Qura Ramadan Isha (open)

The Umm al-Qura timetable uses Isha = Maghrib + 120 min during Ramadan (instead of 90). The
app has no Hijri calendar. To implement it we need a vetted, offline Umm al-Qura month-start
source (a reviewed Dart package or an embedded official table with its citation). Saudi
Ramadan is also announced by moon sighting, which can differ from the calendar by a day, so
the source must be agreed with the scholar. Test kept skipped: "Umm al-Qura: Isha is Maghrib
+ 120 min during Ramadan".

## 4. Per-authority minute adjustments (TODO, needs official tables)

Some authorities publish timetables that add fixed minutes to the astronomical result (for
example a few minutes of "tamkin" on some prayers). The app uses the angles only, so its
times can differ by a few minutes from these official timetables:

* Diyanet (Turkey)
* Dubai / UAE (Awqaf)
* Morocco (Ministry of Habous and Islamic Affairs)
* Jordan (Ministry of Awqaf)

TODO: obtain each authority's official published adjustment table (with the document link
and date), have the Islamic Content Reviewer confirm it, then add per-method minute offsets
and tests against the official timetables. **Do not add numbers before that**; none are
invented here.
