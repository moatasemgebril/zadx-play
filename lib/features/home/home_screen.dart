import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/locations.dart';
import '../../data/catalog/quran.dart';
import '../../router.dart';
import '../../services/audio/audio_service.dart';
import '../../shared/art/zad_art.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../prayer/prayer_calculator.dart';
import '../prayer/prayer_providers.dart';
import '../prayer/prayer_sky_banner.dart';
import '../settings/settings_controller.dart';
import '../tasks/wallet_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final wallet = ref.watch(walletProvider);

    return ZadSceneBackground(
      scene: ZadScene.home,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        _Hero(),
        const SizedBox(height: 12),
        _PromoButton(onTap: () => context.push(Routes.subscription), text: l10n.promoBanner),
        const SizedBox(height: 14),
        const _PrayerCard(),
        const SizedBox(height: 14),
        const _AdhanCard(),
        const SizedBox(height: 14),
        ZadCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const ZadIcon(ZadIconKind.tasks, size: 30),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.tasksToday, style: Theme.of(context).textTheme.titleMedium)),
              Text(
                l10n.progressOf(Fmt.digits(wallet.doneCount, lang), Fmt.digits(wallet.tasks.length, lang)),
                style: const TextStyle(fontSize: 16, color: AppColors.muted),
              ),
            ]),
            const SizedBox(height: 10),
            ProgressBar(value: wallet.tasks.isEmpty ? 0 : wallet.doneCount / wallet.tasks.length, color: AppColors.yellow, height: 12),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Stat(label: l10n.earned, value: l10n.minutesShort(Fmt.digits(wallet.earnedMinutes, lang)), bg: const Color(0xFFFFF4D6))),
              const SizedBox(width: 10),
              Expanded(child: _Stat(label: l10n.played, value: l10n.minutesShort(Fmt.digits(wallet.usedMinutes, lang)), bg: const Color(0xFFE6F7FD))),
            ]),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go(Routes.tasks), child: Text(l10n.goTasks)),
          ]),
        ),
      ]),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        height: 120,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.mintSoft, borderRadius: BorderRadius.circular(24)),
        child: Stack(children: [
          const PositionedDirectional(
            end: 0,
            bottom: 0,
            child: ZadIcon(ZadIconKind.prayer, size: 84),
          ),
          const PositionedDirectional(end: 70, top: 0, child: Icon(Icons.nightlight_round, size: 30, color: AppColors.yellow)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(context.l10n.greet, style: AppTheme.display(26)),
            Text(context.l10n.homeHeroSub, style: const TextStyle(fontSize: 16, color: AppColors.mintText, fontWeight: FontWeight.w700)),
          ]),
        ]),
      );
}

class _PromoButton extends StatelessWidget {
  const _PromoButton({required this.onTap, required this.text});
  final VoidCallback onTap;
  final String text;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.yellow,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(children: [
              const Icon(Icons.workspace_premium_rounded, color: AppColors.purple, size: 28),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            ]),
          ),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.bg});
  final String label;
  final String value;
  final Color bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ]),
      );
}

class _PrayerCard extends ConsumerWidget {
  const _PrayerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final s = ref.watch(settingsProvider);
    final times = ref.watch(prayerTimesProvider);
    final next = ref.watch(nextPrayerProvider);
    final city = cityById(s.cityId);

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const PrayerSkyBanner(),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.prayerToday, style: Theme.of(context).textTheme.titleMedium),
              Text(
                // Arabic comma only in Arabic; English gets a normal comma.
                '${city.name.of(lang)}${lang == 'ar' ? '،' : ','} ${countryById(s.countryId).name.of(lang)} · ${methodById(s.methodId).name.of(lang)}',
                style: const TextStyle(fontSize: 14, color: AppColors.muted),
              ),
            ]),
          ),
          TextButton(onPressed: () => context.push(Routes.settings), child: Text(l10n.change)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (final p in Prayer.values)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: p == next ? AppColors.purple : AppColors.cream,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Text(l10n.prayerName(p), style: TextStyle(fontSize: 15, color: p == next ? Colors.white : AppColors.ink)),
                  const SizedBox(height: 4),
                  Text(
                    Fmt.hours(times.of(p), lang),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: p == next ? Colors.white : AppColors.ink),
                  ),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Text(l10n.nextPrayer(l10n.prayerName(next), Fmt.hours(times.of(next), lang)),
            style: const TextStyle(fontSize: 15, color: AppColors.muted)),
      ]),
    );
  }
}

class _AdhanCard extends ConsumerWidget {
  const _AdhanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final player = ref.watch(playerProvider);
    final playing = player.kind == PlayerKind.adhan;

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.lockBg, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.campaign_rounded, color: Color(0xFFD9415B)),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.adhanTitle, style: Theme.of(context).textTheme.titleMedium),
          ]),
        ]),
        const SizedBox(height: 12),
        if (!playing)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral, foregroundColor: AppColors.ink),
            onPressed: () => ref.read(playerProvider.notifier).playAdhan(),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l10n.hearAdhan),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF3F1), borderRadius: BorderRadius.circular(18)),
            child: Column(children: [
              Text(adhanPhrases[player.index], textAlign: TextAlign.center, style: AppTheme.quran(24)),
              TextButton.icon(
                onPressed: () => ref.read(playerProvider.notifier).stop(),
                icon: const Icon(Icons.stop_rounded),
                label: Text(l10n.stop),
              ),
            ]),
          ),
      ]),
    );
  }
}
