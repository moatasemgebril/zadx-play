namespace ZadX.Guard;

/// <summary>
/// Same algorithm as lib/features/prayer/prayer_calculator.dart (kept in sync; covered
/// by the Dart unit tests). Returns local clock hours for Fajr, Dhuhr, Asr, Maghrib, Isha.
/// </summary>
public static class PrayerTimes
{
    private static double Rad(double d) => d * Math.PI / 180;
    private static double Deg(double r) => r * 180 / Math.PI;
    private static double FixAngle(double a) => (a % 360 + 360) % 360;

    /// <summary>Latitude from which an absent rule (older app) means "relativeEstimation45", as in the app.</summary>
    public const double HighLatitudeAutoFromDegrees = 48.0;

    private static double AngleTimeAt((double Decl, double Eqt) s, double angle, double atLat, bool beforeNoon)
    {
        var x = (-Math.Sin(Rad(angle)) - Math.Sin(Rad(s.Decl)) * Math.Sin(Rad(atLat))) /
                (Math.Cos(Rad(s.Decl)) * Math.Cos(Rad(atLat)));
        if (x < -1 || x > 1) return double.NaN;
        var t = Deg(Math.Acos(x)) / 15;
        return 12 - s.Eqt + (beforeNoon ? -t : t);
    }

    private static (double Decl, double Eqt) SunPosition(double jd)
    {
        var d = jd - 2451545.0;
        var g = FixAngle(357.529 + 0.98560028 * d);
        var q = FixAngle(280.459 + 0.98564736 * d);
        var l = FixAngle(q + 1.915 * Math.Sin(Rad(g)) + 0.020 * Math.Sin(Rad(2 * g)));
        var e = 23.439 - 0.00000036 * d;
        var ra = Deg(Math.Atan2(Math.Cos(Rad(e)) * Math.Sin(Rad(l)), Math.Cos(Rad(l)))) / 15;
        ra = (ra % 24 + 24) % 24;
        var eqt = q / 15 - ra;
        eqt = ((eqt + 12) % 24 + 24) % 24 - 12;
        var decl = Deg(Math.Asin(Math.Sin(Rad(e)) * Math.Sin(Rad(l))));
        return (decl, eqt);
    }

    /// <param name="highLatRule">"relativeEstimation45", "angle12", "middleOfTheNight", "seventhOfTheNight",
    /// "twilightAngle", or null/"none" for no rule. Same definitions as the app
    /// (lib/features/prayer/prayer_calculator.dart).</param>
    public static double[] Compute(DateOnly date, double lat, double lng, double utcOffsetHours,
        double fajrAngle, double? ishaAngle, int? ishaMinutes, int asrFactor, string? highLatRule = null)
    {
        var utcMidnight = new DateTime(date.Year, date.Month, date.Day, 0, 0, 0, DateTimeKind.Utc);
        var jd = (utcMidnight - DateTime.UnixEpoch).TotalMilliseconds / 86400000 + 2440587.5 + 0.5 - lng / 360;

        var sun = SunPosition(jd);
        var noon = 12 - sun.Eqt;

        double AngleTimeFor((double Decl, double Eqt) s, double angle, bool beforeNoon) =>
            AngleTimeAt(s, angle, lat, beforeNoon);

        double AngleTime(double angle, bool beforeNoon) => AngleTimeFor(sun, angle, beforeNoon);

        var fajr = AngleTime(fajrAngle, true);
        var dhuhr = noon + 1.0 / 60;
        var asrAngle = -Deg(Math.Atan(1 / (asrFactor + Math.Tan(Rad(Math.Abs(lat - sun.Decl))))));
        var asr = AngleTime(asrAngle, false);
        var maghrib = AngleTime(0.833, false);
        var isha = ishaMinutes is int m ? maghrib + m / 60.0 : AngleTime(ishaAngle ?? 17, false);

        (double Fajr, double Isha)? portions = highLatRule switch
        {
            "middleOfTheNight" => (1.0 / 2, 1.0 / 2),
            "seventhOfTheNight" => (1.0 / 7, 1.0 / 7),
            "twilightAngle" => (fajrAngle / 60, (ishaAngle ?? 0) / 60),
            _ => null,
        };
        if (highLatRule is "relativeEstimation45" or "angle12")
        {
            // ECFR: only on a day without the sign (the method's angle is not reached).
            var sunrise = AngleTime(0.833, true);
            var nextSun = SunPosition(jd + 1);
            var night = 24 + AngleTimeFor(nextSun, 0.833, true) - maghrib;
            if (!double.IsNaN(sunrise) && !double.IsNaN(night) && night > 0)
            {
                var refLat = lat < 0 ? -45.0 : 45.0;
                var m45 = AngleTimeAt(sun, 0.833, refLat, false);
                var sr45 = AngleTimeAt(sun, 0.833, refLat, true);
                var night45 = 24 + AngleTimeAt(nextSun, 0.833, refLat, true) - m45;
                var fajrShare = (sr45 - AngleTimeAt(sun, fajrAngle, refLat, true)) / night45;
                var ishaShare = (AngleTimeAt(sun, ishaAngle ?? 17, refLat, false) - m45) / night45;
                if (double.IsNaN(fajr))
                {
                    if (highLatRule == "angle12") fajr = AngleTime(12, true);
                    if (double.IsNaN(fajr)) fajr = sunrise - fajrShare * night;
                }
                if (ishaMinutes is null && double.IsNaN(isha))
                {
                    if (highLatRule == "angle12") isha = AngleTime(12, false);
                    if (double.IsNaN(isha)) isha = maghrib + ishaShare * night;
                }
            }
        }
        else if (portions is { } portion)
        {
            var (fajrPortion, ishaPortion) = portion;
            var sunrise = AngleTime(0.833, true);
            var nextSunrise = 24 + AngleTimeFor(SunPosition(jd + 1), 0.833, true);
            var night = nextSunrise - maghrib;
            if (!double.IsNaN(sunrise) && !double.IsNaN(night) && night > 0)
            {
                var safeFajr = sunrise - fajrPortion * night;
                if (double.IsNaN(fajr) || safeFajr > fajr) fajr = safeFajr;
                if (ishaMinutes is null)
                {
                    var safeIsha = maghrib + ishaPortion * night;
                    if (double.IsNaN(isha) || safeIsha < isha) isha = safeIsha;
                }
            }
        }

        var adjust = utcOffsetHours - lng / 15;
        return new[] { fajr, dhuhr, asr, maghrib, isha }.Select(t => t + adjust).ToArray();
    }

    /// <summary>The rule to use: the app's synced choice, or (older apps that do not sync one)
    /// "twilightAngle" from 48° latitude, the app's default.</summary>
    public static string? EffectiveHighLatRule(PrayerSettings p) =>
        p.HighLatRule switch
        {
            null => p.Lat is double lat && Math.Abs(lat) >= HighLatitudeAutoFromDegrees ? "relativeEstimation45" : null,
            "none" => null,
            var rule => rule,
        };

    /// <summary>True during the first <paramref name="lockMinutes"/> after any adhan today.</summary>
    public static bool InPrayerWindow(PrayerSettings p, int lockMinutes)
    {
        if (!p.LockAtAdhan || p.Lat is null || p.Lng is null || p.FajrAngle is null) return false;
        TimeZoneInfo tz;
        try { tz = TimeZoneInfo.FindSystemTimeZoneById(p.TimeZone); } // IANA ids work on .NET 6+ with ICU
        catch (TimeZoneNotFoundException) { tz = TimeZoneInfo.Local; }

        var nowLocal = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, tz);
        var times = Compute(DateOnly.FromDateTime(nowLocal.DateTime), p.Lat.Value, p.Lng.Value,
            nowLocal.Offset.TotalHours, p.FajrAngle.Value, p.IshaAngle, p.IshaMinutes, p.AsrFactor,
            EffectiveHighLatRule(p));
        var nowHours = nowLocal.Hour + nowLocal.Minute / 60.0;
        return times.Any(t => !double.IsNaN(t) && nowHours >= t && nowHours < t + lockMinutes / 60.0);
    }
}
