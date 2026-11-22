import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/adhkar.dart';
import '../../shared/widgets/zad_widgets.dart';
import 'adhkar_controller.dart';

/// Morning / evening adhkar and salawat with a tap-to-count tasbeeh per dhikr.
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
  const _DhikrCard({required this.dhikr, required this.count, required this.onTap, required this.onReset});
  final Dhikr dhikr;
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
