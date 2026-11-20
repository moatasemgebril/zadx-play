import 'package:flutter/widgets.dart';

import '../features/prayer/prayer_calculator.dart';
import '../l10n/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
  String get lang => Localizations.localeOf(this).languageCode;
}

extension PrayerNames on AppLocalizations {
  String prayerName(Prayer p) => switch (p) {
        Prayer.fajr => fajr,
        Prayer.dhuhr => dhuhr,
        Prayer.asr => asr,
        Prayer.maghrib => maghrib,
        Prayer.isha => isha,
      };
}
