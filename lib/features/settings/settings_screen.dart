import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../data/catalog/locations.dart';
import '../../shared/art/zad_art.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../prayer/city_time_zone.dart';
import '../prayer/prayer_calculator.dart';
import '../prayer/prayer_schedule.dart';
import '../prayer/prayer_providers.dart';
import '../../core/utils/formatters.dart';
import '../parent/devices_card.dart';
import 'settings_controller.dart';

/// True when, in the next 7 days, the chosen high-latitude rule puts Isha at or after the next
/// Fajr in the selected city (see `planAdhanNotifications`).
bool _ishaMeetsFajrSoon(AppSettings s) {
  final city = cityById(s.cityId);
  final rule = resolveHighLatitudeRule(s.highLatitude, city.lat);
  if (rule == null) return false;
  final location = cityLocation(city);
  final today = tz.TZDateTime.now(location);
  for (var i = 0; i < 7; i++) {
    final d = DateTime.utc(today.year, today.month, today.day + i);
    if (ishaReachesNextFajr(
      location: location,
      year: d.year,
      month: d.month,
      day: d.day,
      lat: city.lat,
      lng: city.lng,
      method: methodById(s.methodId),
      highLatitudeRule: rule,
      hijriAdjustmentDays: s.hijriAdjustmentDays,
    )) {
      return true;
    }
  }
  return false;
}

/// Language, country, city and prayer calculation (globe icon in the header).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final times = ref.watch(prayerTimesProvider);

    final langItems = [...supportedLanguages, ...upcomingLanguages.keys];
    String langLabel(String code) => switch (code) {
          'ar' => 'العربية',
          'en' => 'English',
          _ => upcomingLanguages[code]!,
        };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle), backgroundColor: AppColors.navy, foregroundColor: Colors.white),
      body: ZadSceneBackground(
        scene: ZadScene.parent,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _Section(
            title: l10n.language,
            child: ChoiceGrid<String>(
              items: langItems,
              selected: s.language,
              label: langLabel,
              disabled: (c) => !supportedLanguages.contains(c),
              note: (c) => supportedLanguages.contains(c) ? null : l10n.soon,
              onSelected: ctrl.setLanguage,
            ),
          ),
          _Section(
            title: l10n.country,
            child: ChoiceGrid<String>(
              items: countries.map((c) => c.id).toList(),
              selected: s.countryId,
              label: (id) => countryById(id).name.of(lang),
              onSelected: ctrl.setCountry,
            ),
          ),
          _Section(
            title: l10n.city,
            child: ChoiceGrid<String>(
              items: citiesOf(s.countryId).map((c) => c.id).toList(),
              selected: s.cityId,
              label: (id) => cityById(id).name.of(lang),
              onSelected: ctrl.setCity,
            ),
          ),
          _Section(
            title: l10n.method,
            child: ChoiceGrid<String>(
              items: calcMethods.keys.toList(),
              selected: s.methodId,
              columns: 2,
              label: (id) => methodById(id).name.of(lang),
              onSelected: ctrl.setMethod,
            ),
          ),
          _Section(
            title: l10n.asrCalc,
            child: ChoiceGrid<int>(
              items: const [1, 2],
              selected: s.asrFactor,
              columns: 2,
              label: (f) => f == 1 ? l10n.asrStandard : l10n.asrHanafi,
              onSelected: ctrl.setAsrFactor,
            ),
          ),
          _Section(
            title: l10n.highLatitudeRule,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChoiceGrid<HighLatitudeSetting>(
                  items: HighLatitudeSetting.values,
                  selected: s.highLatitude,
                  columns: 2,
                  label: (v) => switch (v) {
                    HighLatitudeSetting.auto => l10n.highLatitudeAuto,
                    HighLatitudeSetting.relativeEstimation45 => l10n.highLatitudeRelative45,
                    HighLatitudeSetting.angle12 => l10n.highLatitudeAngle12,
                    HighLatitudeSetting.middleOfTheNight => l10n.highLatitudeMiddleOfNight,
                    HighLatitudeSetting.seventhOfTheNight => l10n.highLatitudeSeventhOfNight,
                    HighLatitudeSetting.twilightAngle => l10n.highLatitudeTwilightAngle,
                  },
                  onSelected: ctrl.setHighLatitude,
                ),
                const SizedBox(height: 8),
                Text(l10n.highLatitudeHelp, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                const SizedBox(height: 4),
                Text(
                  l10n.highLatitudeSource,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.muted),
                ),
                // With a night-portion rule, Isha can fall at/after the next Fajr in summer: its adhan
                // is skipped (never Isha itself) and the parent is told combining is permitted.
                if (_ishaMeetsFajrSoon(s)) ...[
                  const SizedBox(height: 8),
                  Banner2(text: l10n.ishaCombineNote, bg: AppColors.pendingBg, fg: AppColors.pendingText, icon: Icons.info_outline_rounded),
                ],
              ],
            ),
          ),
          ZadCard(
            color: AppColors.cream,
            child: Text(
              Prayer.values.map((p) => '${l10n.prayerName(p)} ${Fmt.hours(times.of(p), lang)}').join(' · '),
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          const JoinFamilyCard(),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ZadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.muted)),
            const SizedBox(height: 8),
            child,
          ]),
        ),
      );
}
