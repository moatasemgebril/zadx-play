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

    public static double[] Compute(DateOnly date, double lat, double lng, double utcOffsetHours,
        double fajrAngle, double? ishaAngle, int? ishaMinutes, int asrFactor)
    {
        var utcMidnight = new DateTime(date.Year, date.Month, date.Day, 0, 0, 0, DateTimeKind.Utc);
        var jd = (utcMidnight - DateTime.UnixEpoch).TotalMilliseconds / 86400000 + 2440587.5 + 0.5 - lng / 360;

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
        var noon = 12 - eqt;

        double AngleTime(double angle, bool beforeNoon)
        {
            var x = (-Math.Sin(Rad(angle)) - Math.Sin(Rad(decl)) * Math.Sin(Rad(lat))) /
                    (Math.Cos(Rad(decl)) * Math.Cos(Rad(lat)));
            if (x < -1 || x > 1) return double.NaN;
            var t = Deg(Math.Acos(x)) / 15;
            return noon + (beforeNoon ? -t : t);
        }

        var fajr = AngleTime(fajrAngle, true);
        var dhuhr = noon + 1.0 / 60;
        var asrAngle = -Deg(Math.Atan(1 / (asrFactor + Math.Tan(Rad(Math.Abs(lat - decl))))));
        var asr = AngleTime(asrAngle, false);
        var maghrib = AngleTime(0.833, false);
        var isha = ishaMinutes is int m ? maghrib + m / 60.0 : AngleTime(ishaAngle ?? 17, false);

        var adjust = utcOffsetHours - lng / 15;
        return new[] { fajr, dhuhr, asr, maghrib, isha }.Select(t => t + adjust).ToArray();
    }

    /// <summary>True during the first <paramref name="lockMinutes"/> after any adhan today.</summary>
    public static bool InPrayerWindow(PrayerSettings p, int lockMinutes)
    {
        if (!p.LockAtAdhan || p.Lat is null || p.Lng is null || p.FajrAngle is null) return false;
        TimeZoneInfo tz;
        try { tz = TimeZoneInfo.FindSystemTimeZoneById(p.TimeZone); } // IANA ids work on .NET 6+ with ICU
        catch (TimeZoneNotFoundException) { tz = TimeZoneInfo.Local; }

        var nowLocal = TimeZoneInfo.ConvertTime(DateTimeOffset.UtcNow, tz);
        var times = Compute(DateOnly.FromDateTime(nowLocal.DateTime), p.Lat.Value, p.Lng.Value,
            nowLocal.Offset.TotalHours, p.FajrAngle.Value, p.IshaAngle, p.IshaMinutes, p.AsrFactor);
        var nowHours = nowLocal.Hour + nowLocal.Minute / 60.0;
        return times.Any(t => !double.IsNaN(t) && nowHours >= t && nowHours < t + lockMinutes / 60.0);
    }
}
