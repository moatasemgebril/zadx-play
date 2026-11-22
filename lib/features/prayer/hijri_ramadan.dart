import 'package:hijri/hijri_calendar.dart';

import '../../data/models/location.dart';

// Umm al-Qura Ramadan detection for the Ramadan Isha rule (Isha = Maghrib + 120 min).
//
// Rule: Saudi Press Agency, https://www.spa.gov.sa/907467 (decision record:
// docs/decisions/PRAYER-TIMES-ACCURACY.md section 3).
//
// Calendar: the pub.dev package `hijri` (BSD-2-Clause), whose documentation describes its
// conversion as the Umm al-Qura calendar ("From Gregorian to Ummalqura"). Its table is not
// traced to KACST in its documentation, so the parent can move the Hijri date by one day
// ([hijriAdjustmentChoices]); Ramadan in Saudi Arabia is also announced by moon sighting,
// which can differ from the printed calendar by a day.
//
// The rule follows the calendar day: on every Gregorian day whose Umm al-Qura date
// (after the parent's adjustment) is in Ramadan (month 9), Isha is Maghrib + 120 min.

/// Values the parent can pick: the month started one day later than the calendar (-1),
/// as the calendar (0), or one day earlier (+1).
const hijriAdjustmentChoices = [-1, 0, 1];

/// Clamps a stored value to [hijriAdjustmentChoices].
int clampHijriAdjustment(int days) => days.clamp(-1, 1);

/// The Umm al-Qura Hijri month (1-12) of the Gregorian calendar day [year]-[month]-[day],
/// shifted by [adjustmentDays] (see [hijriAdjustmentChoices]). `null` if the calendar table
/// does not cover the date.
int? ummAlQuraHijriMonth(int year, int month, int day, {int adjustmentDays = 0}) {
  // Noon, plain calendar arithmetic: the Hijri date of that Gregorian day, never an hour off.
  final d = DateTime(year, month, day + clampHijriAdjustment(adjustmentDays), 12);
  try {
    final h = HijriCalendar.fromDate(d);
    final m = h.hMonth;
    return m >= 1 && m <= 12 ? m : null;
  } catch (_) {
    return null; // outside the package's table: no Ramadan rule rather than a wrong one
  }
}

/// True when [year]-[month]-[day] is in Ramadan of the Umm al-Qura calendar.
bool isUmmAlQuraRamadan(int year, int month, int day, {int adjustmentDays = 0}) =>
    ummAlQuraHijriMonth(year, month, day, adjustmentDays: adjustmentDays) == 9;

/// Minutes from Maghrib to Isha for [method] on that day (`null` = angle-based Isha).
/// Only a method with [CalcMethod.ishaMinutesAfterMaghribInRamadan] (Umm al-Qura) changes
/// in Ramadan; every other method returns its usual interval.
int? ishaIntervalOn(CalcMethod method, int year, int month, int day, {int hijriAdjustmentDays = 0}) {
  final inRamadan = method.ishaMinutesAfterMaghribInRamadan;
  if (inRamadan != null && isUmmAlQuraRamadan(year, month, day, adjustmentDays: hijriAdjustmentDays)) {
    return inRamadan;
  }
  return method.ishaMinutesAfterMaghrib;
}
