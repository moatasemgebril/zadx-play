import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/quran.dart';
import '../../data/catalog/surah_index.dart';
import '../../data/models/surah.dart';
import '../../services/audio/audio_service.dart';
import '../../services/quran/quran_repository.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../adhkar/adhkar_view.dart';
import '../settings/settings_controller.dart';

const _badgeColors = [Color(0xFFFFC83D), Color(0xFF4CC9F0), Color(0xFFFF6B6B), Color(0xFF7ED9B8), Color(0xFFC4B5FD), Color(0xFFFFB38A)];

/// Quran (Juz 30, Juz 29 + Al-Fatiha) and Adhkar.
class QuranScreen extends StatelessWidget {
  const QuranScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PatternBackground(
      tint: AppColors.pageTints['quran']!,
      seed: 3,
      child: DefaultTabController(
        length: 3,
        child: Column(children: [
          Material(
            color: Colors.white,
            child: TabBar(
              labelStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              unselectedLabelStyle: const TextStyle(fontSize: 16),
              labelColor: AppColors.purpleDark,
              indicatorColor: AppColors.purple,
              tabs: [Tab(text: l10n.juz30), Tab(text: l10n.juz29), Tab(text: l10n.adhkar)],
            ),
          ),
          const Expanded(
            child: TabBarView(children: [
              _SurahList(juz: 30, includeFatiha: true),
              _SurahList(juz: 29),
              AdhkarView(),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _SurahList extends ConsumerWidget {
  const _SurahList({required this.juz, this.includeFatiha = false});
  final int juz;
  final bool includeFatiha;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final s = ref.watch(settingsProvider);
    final list = [
      if (includeFatiha) surahIndex.first,
      ...surahsOfJuz(juz),
    ];

    return ListView(padding: const EdgeInsets.all(16), children: [
      ZadCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l10n.chooseReciter, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.muted)),
          const SizedBox(height: 8),
          ChoiceGrid(
            items: reciters.map((r) => r.id).toList(),
            selected: s.reciterId,
            columns: 2,
            label: (id) => reciters.firstWhere((r) => r.id == id).name.of(lang),
            onSelected: ref.read(settingsProvider.notifier).setReciter,
          ),
        ]),
      ),
      const SizedBox(height: 12),
      for (var i = 0; i < list.length; i++) ...[
        _SurahCard(surah: list[i], color: _badgeColors[i % _badgeColors.length]),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _SurahCard extends ConsumerWidget {
  const _SurahCard({required this.surah, required this.color});
  final SurahInfo surah;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final player = ref.watch(playerProvider);
    final playing = player.kind == PlayerKind.quran && player.surahNumber == surah.number;
    final name = surah.name.of(lang);

    return ZadCard(
      border: playing ? Border.all(color: const Color(0xFFC4B5FD), width: 3) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
            child: Text(Fmt.digits(surah.number, lang), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              Text(l10n.ayatCount(Fmt.digits(surah.ayahCount, lang)), style: const TextStyle(fontSize: 15, color: AppColors.muted)),
            ]),
          ),
          IconButton.filled(
            tooltip: playing ? l10n.stop : l10n.playSurah(name),
            style: IconButton.styleFrom(
              backgroundColor: playing ? AppColors.coral : AppColors.purple,
              foregroundColor: playing ? AppColors.ink : Colors.white,
              minimumSize: const Size(52, 52),
            ),
            onPressed: () => playing
                ? ref.read(playerProvider.notifier).stop()
                : ref.read(playerProvider.notifier).playSurah(surah),
            icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
          ),
        ]),
        if (playing) ...[
          const SizedBox(height: 10),
          ProgressBar(value: player.progress ?? (player.index + 1) / surah.ayahCount, color: AppColors.purple, height: 6),
          const SizedBox(height: 8),
          _AyatText(surah: surah, currentIndex: player.index),
        ],
      ]),
    );
  }
}

class _AyatText extends ConsumerWidget {
  const _AyatText({required this.surah, required this.currentIndex});
  final SurahInfo surah;
  final int currentIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = ref.watch(surahTextProvider(surah.number));
    return text.when(
      loading: () => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(l10n.loadingText, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
      ),
      error: (_, __) => Banner2(text: l10n.textError, bg: AppColors.lockBg, fg: AppColors.lockText),
      data: (ayat) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var a = 0; a < ayat.length; a++)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: a == currentIndex ? AppColors.pendingBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${ayat[a]} ﴿${Fmt.digits(a + 1, 'ar')}﴾',
              textDirection: TextDirection.rtl,
              style: AppTheme.quran(22, color: a == currentIndex ? AppColors.ink : AppColors.muted),
            ),
          ),
      ]),
    );
  }
}
