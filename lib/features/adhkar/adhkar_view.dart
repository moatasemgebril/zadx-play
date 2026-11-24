import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/adhkar.dart';
import '../../data/catalog/quran.dart';
import '../../data/models/quran_ref.dart';
import '../../data/models/surah.dart';
import '../../services/audio/audio_service.dart';
import '../../shared/widgets/zad_widgets.dart';
import 'adhkar_controller.dart';

/// The reciter of Quranic adhkar (Alafasy), or null when release builds may not offer
/// him (licence not confirmed): then no play button is shown at all.
final adhkarReciterProvider = Provider<Voice?>((ref) => adhkarReciter());

/// Morning / evening adhkar and salawat with a tap-to-count tasbeeh per dhikr.
///
/// Only Quran ayat get audio (owner decision 2026-11-23): the three Quls of the reminder card
/// and any dhikr with [Dhikr.quran], recited by Mishary Alafasy through the licensed Quran
/// pipeline. Every other dhikr is text-only (no licence for adhkar recordings).
class AdhkarView extends ConsumerStatefulWidget {
  const AdhkarView({super.key});

  @override
  ConsumerState<AdhkarView> createState() => _AdhkarViewState();
}

class _AdhkarViewState extends ConsumerState<AdhkarView> {
  AdhkarSection _section = DateTime.now().hour < 15 ? AdhkarSection.morning : AdhkarSection.evening;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    ref.watch(adhkarProvider);
    final ctrl = ref.read(adhkarProvider.notifier);
    final items = adhkar[_section]!;
    final done = ctrl.isSectionDone(_section);
    final reciter = ref.watch(adhkarReciterProvider);

    String label(AdhkarSection s) => switch (s) {
          AdhkarSection.morning => l10n.morningAdhkar,
          AdhkarSection.evening => l10n.eveningAdhkar,
          AdhkarSection.salawat => l10n.salawat,
        };

    return ListView(padding: const EdgeInsets.all(16), children: [
      ChoiceGrid<AdhkarSection>(
        items: AdhkarSection.values,
        selected: _section,
        label: label,
        onSelected: (s) => setState(() => _section = s),
      ),
      const SizedBox(height: 12),
      if (_section != AdhkarSection.salawat) ...[
        Banner2(text: qulsReminder.of(lang), bg: AppColors.purpleSoft, fg: AppColors.purpleDark, icon: Icons.menu_book_rounded),
        const SizedBox(height: 10),
        if (reciter != null) ...[
          ZadCard(child: QuranListenPanel(refs: qulsRefs, reciter: reciter)),
          const SizedBox(height: 10),
        ],
      ] else ...[
        Banner2(text: salawatReminder.of(lang), bg: AppColors.purpleSoft, fg: AppColors.purpleDark, icon: Icons.favorite_rounded),
        const SizedBox(height: 10),
      ],
      if (done) ...[
        Banner2(text: l10n.sectionDone, bg: AppColors.mintSoft, fg: AppColors.mintText, icon: Icons.celebration_rounded),
        const SizedBox(height: 10),
      ],
      for (final d in items) ...[
        _DhikrCard(
          dhikr: d,
          reciter: reciter,
          count: ctrl.count(d.id),
          onTap: () {
            HapticFeedback.selectionClick();
            final before = ctrl.isSectionDone(_section);
            ctrl.tap(_section, d);
            if (!before && ctrl.isSectionDone(_section)) showToast(context, l10n.sectionDone);
          },
          onReset: () => ctrl.reset(d),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _DhikrCard extends StatelessWidget {
  const _DhikrCard({required this.dhikr, required this.reciter, required this.count, required this.onTap, required this.onReset});
  final Dhikr dhikr;

  /// The licensed adhkar reciter, or null (no audio). Used only when [Dhikr.quran] is set.
  final Voice? reciter;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final complete = count >= dhikr.times;

    return ZadCard(
      border: complete ? Border.all(color: AppColors.mint, width: 3) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(dhikr.text, textDirection: TextDirection.rtl, style: AppTheme.quran(21)),
        if (dhikr.note != null)
          Text(
            dhikr.note!.of(lang),
            textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(fontSize: 14, color: AppColors.purpleDark),
          ),
        const SizedBox(height: 4),
        Text(
          dhikr.sourceOf(lang),
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        if (dhikr.quran != null && reciter != null) ...[
          const SizedBox(height: 10),
          QuranListenPanel(refs: [dhikr.quran!], reciter: reciter!),
        ],
        const SizedBox(height: 10),
        ProgressBar(value: count / dhikr.times, color: complete ? AppColors.mint : AppColors.yellow),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              // "0 / 1" rather than "0 / 1 times" (EN) or "٠ / ١ مرات" (AR): the plural word is wrong for 1.
              '${Fmt.digits(count, lang)} / ${dhikr.times == 1 ? Fmt.digits(1, lang) : l10n.dhikrTimes(dhikr.times, Fmt.digits(dhikr.times, lang))}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.purpleDark),
            ),
          ),
          if (count > 0) TextButton(onPressed: onReset, child: Text(l10n.resetCount)),
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(110, 56),
              backgroundColor: complete ? AppColors.mintSoft : AppColors.purple,
              foregroundColor: complete ? AppColors.mintText : Colors.white,
            ),
            onPressed: complete ? null : onTap,
            child: complete ? const Icon(Icons.check_rounded) : Text(l10n.tapToCount),
          ),
        ]),
      ]),
    );
  }
}

/// Play / stop buttons for Quran ayat in the adhkar screen, the reciter credit
/// («مشاري العفاسي · Mishary Alafasy») and, when the recitation cannot start (offline),
/// a gentle inline hint instead of an error dialog.
class QuranListenPanel extends StatefulWidget {
  const QuranListenPanel({super.key, required this.refs, required this.reciter});
  final List<QuranRef> refs;
  final Voice reciter;

  @override
  State<QuranListenPanel> createState() => _QuranListenPanelState();
}

class _QuranListenPanelState extends State<QuranListenPanel> {
  bool _offline = false;

  void _onResult(bool started) {
    if (!mounted) return;
    if (_offline == !started) return;
    setState(() => _offline = !started);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final r in widget.refs) QuranListenButton(key: QuranListenButton.keyFor(r), quranRef: r, reciter: widget.reciter, onResult: _onResult),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        const Icon(Icons.record_voice_over_rounded, size: 18, color: AppColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            reciterCredit(widget.reciter),
            textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
            style: const TextStyle(fontSize: 14, color: AppColors.muted),
          ),
        ),
      ]),
      if (_offline) ...[
        const SizedBox(height: 8),
        Banner2(text: l10n.quranListenOffline, bg: AppColors.pendingBg, fg: AppColors.pendingText, icon: Icons.wifi_off_rounded),
      ],
    ]);
  }
}

/// One play / stop button for [quranRef], played as Quran ([PlayerKind.quran]).
class QuranListenButton extends ConsumerWidget {
  const QuranListenButton({super.key, required this.quranRef, required this.reciter, required this.onResult});

  /// Key of the button for [r] (tests find buttons by it).
  static Key keyFor(QuranRef r) => ValueKey('quran-listen-${r.key}');

  final QuranRef quranRef;
  final Voice reciter;

  /// Called with true when the recitation started, false when it could not (offline).
  final ValueChanged<bool> onResult;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final player = ref.watch(playerProvider);
    final playing = player.kind == PlayerKind.quran && player.refKey == quranRef.key;
    final surah = surahOfRef(quranRef);
    final name = surah?.name.of(lang) ?? Fmt.digits(quranRef.surah, lang);
    final whole = surah != null && quranRef.fromAyah == 1 && quranRef.toAyah == surah.ayahCount;
    final label = whole
        ? name
        : '$name ${Fmt.digits(quranRef.fromAyah, lang)}–${Fmt.digits(quranRef.toAyah, lang)}';

    return Tooltip(
      message: playing ? l10n.stop : l10n.playSurah(label),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(110, 56),
          backgroundColor: playing ? AppColors.coral : AppColors.purple,
          foregroundColor: playing ? AppColors.ink : Colors.white,
        ),
        onPressed: () async {
          final notifier = ref.read(playerProvider.notifier);
          if (playing) {
            await notifier.stop();
            return;
          }
          onResult(await notifier.playQuranRef(quranRef, reciter));
        },
        icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
    );
  }
}
