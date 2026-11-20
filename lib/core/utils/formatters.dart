/// Number and time helpers that respect the chosen language.
class Fmt {
  const Fmt._();

  static const _arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

  static String digits(Object value, String lang) {
    final s = value.toString();
    if (lang != 'ar') return s;
    return s.replaceAllMapped(RegExp(r'\d'), (m) => _arabicDigits[int.parse(m[0]!)]);
  }

  /// Formats a local time expressed as fractional hours (e.g. 15.42) as "3:25 م".
  static String hours(double h, String lang) {
    if (h.isNaN || h.isInfinite) return '--';
    var total = ((h % 24 + 24) % 24 * 60).round() % 1440;
    final hh = total ~/ 60;
    final mm = total % 60;
    final ampm = hh < 12 ? (lang == 'ar' ? 'ص' : 'AM') : (lang == 'ar' ? 'م' : 'PM');
    final h12 = hh % 12 == 0 ? 12 : hh % 12;
    return '${digits('$h12:${mm.toString().padLeft(2, '0')}', lang)} $ampm';
  }

  static String usd(double v) => '\$${v.toStringAsFixed(2)}';
}
