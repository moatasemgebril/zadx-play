# Prayer times: accuracy decisions and open items

Status: 2026-11-22. Owner decision: no sheikh sign-off gate; decisions below are applied from
the cited official / trusted sources. Nothing here invents religious rulings or official
timetable numbers.

## 1. High-latitude rule (decided 2026-11-22)

Owner decision 2026-11-22: no sheikh sign-off gate; apply decisions verified from official /
trusted sources. Source for the rules: European Council for Fatwa and Research (ECFR)
resolution 41 (2/12) and the MWL Islamic Fiqh Academy (relative estimation); ECFR resolution 3/3
(combining Maghrib and Isha when Isha's sign is absent).

Far from the equator the sun does not go 17-18° below the horizon on summer nights, so
angle-based Fajr and Isha do not exist (London: about 21 May to 23 July for 18°). Without a
rule there is no Fajr/Isha time, no adhan and no prayer lock for those weeks.

Parent setting: Settings > "High-latitude rule", with the source note «وفق قرار المجلس الأوروبي
للإفتاء 41 (2/12)» / "Per ECFR resolution 41 (2/12)" (the old "pending scholar review" label is gone).

| Option | What it does |
|---|---|
| **Automatic** (default) | Relative estimation from 45° at latitudes of 48° and above; no rule below 48°. |
| Relative estimation from latitude 45° (ECFR / MWL Fiqh Academy) | On a day when the method's angle is **not reached** (no sign), compute at latitude 45° (same hemisphere, same longitude, same date, same method angles) the shares f_isha = (Maghrib→Isha) / night and f_fajr = (Fajr→sunrise) / night, and apply them to the local night: Isha = sunset + f_isha × night, Fajr = sunrise − f_fajr × night. On days with a real sign the real time is kept. |
| 12° angle for Fajr and Isha (ECFR permits) | On a day the method's angle is not reached, use 12°; where even 12° is not reached (e.g. Oslo/Reykjavik in June), the 45° relative estimation. |
| Middle of the night / One-seventh / Twilight angle | adhan-library (batoulapps) / PrayTimes.org night-portion bounds, kept as options. |

The night is sunset to the next sunrise.

Engineering note on "only on days without the sign": applying the 45° shares on every day would
move Isha 10 (London) to 50+ (Reykjavik) minutes **earlier than the real sign** even in winter
(measured with the app's algorithm), i.e. before Isha's time when its sign exists. The rule
therefore fills only the missing times, which is the case the resolutions address. Consequence:
on the first and last days of the "no sign" season the time jumps (the real late Isha one day,
the estimated earlier Isha the next). Verified for London, Paris, Berlin, Oslo, Reykjavik with
the MWL, Egypt, ISNA, Karachi, UOIF, Kemenag and Dubai angles on every day of 2026: Fajr/Isha
always exist, Fajr < sunrise, Isha > Maghrib and Isha < next Fajr.

* A fixed-interval Isha (Umm al-Qura, Qatar: Maghrib + 90 min) is never moved by a rule.
* **Isha at or after the next Fajr** (possible only with the night-portion options, e.g. "Middle
  of the night" in July at 60°N): Isha is **not dropped**. Only its adhan sound is skipped; a
  silent Isha reminder is planned one minute after Maghrib, the Isha time stays visible, and the
  parent sees in Settings: «يجوز الجمع بين المغرب والعشاء عند فقد علامة العشاء (قرار المجلس
  الأوروبي 3/3)» / "Combining Maghrib and Isha is permitted when Isha's sign is absent (ECFR 3/3)".
  Never happens with the 45° rule (tested).
* Wired into: displayed times (`prayerTimesProvider`), adhan notifications
  (`planAdhanNotifications`), the phone prayer lock (`app_lock_service`), and Windows Guard
  (synced as `settings.highLatRule`, passed by the `devicePolicy` function; an older app that
  does not sync it gets the same default on the guard: `relativeEstimation45` from 48°).

Code: `lib/features/prayer/prayer_calculator.dart`, `lib/features/prayer/prayer_schedule.dart`,
`windows_guard/PrayerTimes.cs`. Tests: `test/prayer_times_world_test.dart` group "high latitudes"
(London/Paris/Berlin/Oslo/Reykjavik on 20 May, 21 Jun, 10 Jul, 21 Dec, against the independent
NOAA/Meeus reference).

## 2. Morocco time zone (fixed)

IANA tzdata 2026c (released 2026-07-08, https://www.iana.org/time-zones/releases/2026c):
"Morocco plans to move back to permanent UTC, without daylight saving time transitions, on
2026-09-20 at 02:00." The bundled `timezone` 0.10.1 (newest allowed by
flutter_local_notifications 18) predates it. `lib/features/prayer/city_time_zone.dart` uses
UTC for Africa/Casablanca and Africa/El_Aaiun while the bundled data is stale, and switches
itself off when a newer database has +00. Remove it after the planned
flutter_local_notifications / timezone upgrade.

## 3. Umm al-Qura Ramadan Isha (rule confirmed; not implemented)

Rule confirmed: in Ramadan the Umm al-Qura timetable uses Isha = Maghrib + 120 min (instead of
90). Source: Saudi Press Agency, https://www.spa.gov.sa/907467 . The calendar authority for the
Umm al-Qura calendar is KACST (King Abdulaziz City for Science and Technology).

Not implemented (2026-11-22): no official downloadable Umm al-Qura Hijri table was found, no
Hijri package is in `pubspec.yaml`, and no pub.dev package's data source could be verified
against KACST from this environment. Adding an unverified table could put Isha 30 minutes off
for a whole day or the whole month, so the test "Umm al-Qura: Isha is Maghrib + 120 min during
Ramadan" stays skipped. To finish: add a vetted offline Umm al-Qura package (data traced to
KACST), a parent ±1 day adjustment (moon sighting can differ from the calendar), and enable
the test.

## 4. Per-authority minute adjustments (decided: none)

Some authorities' timetables may add fixed minutes to the astronomical result ("tamkin").
No authority below publishes its adjustment values officially, so **no offsets are applied**
(owner decision 2026-11-22, verified-sources report). The app uses each method's published
angles only and may differ by a few minutes from these printed timetables:

* Diyanet (Turkey)
* Dubai / UAE (Awqaf)
* Morocco (Ministry of Habous and Islamic Affairs)
* Jordan (Ministry of Awqaf)

Revisit only if an authority publishes its adjustment table officially (with document link
and date); never add numbers from unofficial sites.

## 5. Excused (menstruation) option (decided 2026-11-22)

Sources: Dar al-Ifta al-Misriyya fatwa 7711 (https://dar-alifta.org/ar/fatwa/details/19049/) and
Ibn Baz fatwa 13476: a menstruating girl does not pray and does not make the prayers up.

Built as a parent-only (parent area, behind the PIN; parent devices only in
`backend/firestore.rules`) per-day, per-child toggle «إيقاف مهام الصلاة مؤقتًا (عذر)» / "Pause prayer
tasks (excused)". It pauses that child's prayer tasks and prayer lock (phone alarms, app lock,
Windows Guard via `devicePolicy.prayerPaused`) for that day; minutes and stars already earned are
not touched and prayer tasks do not count as missed. Nothing is sent to the family log or other
children's devices; the child only sees «مهامّك الأخرى متاحة اليوم» / "Your other tasks are open
today", with no reason. Adhkar stay available. Stored as `prayerPaused` on the child's day doc.
Shown for children addressed as a girl or not set. Not in the Kids variant.

Known limit: Windows Guard reads the server `requiredDone`, recomputed by `approveTask`; after a
pause it reflects the pause from the next approval of that day.
