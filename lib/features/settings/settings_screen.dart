import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../data/catalog/locations.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../prayer/prayer_calculator.dart';
import '../prayer/prayer_providers.dart';
import '../../core/utils/formatters.dart';
import '../parent/devices_card.dart';
import 'settings_controller.dart';

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
      body: PatternBackground(
        tint: AppColors.pageTints['parent']!,
        seed: 6,
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
