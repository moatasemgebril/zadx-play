import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/family_task.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../tasks/wallet_controller.dart';
import 'reading_screen.dart';
import 'reading_tasks.dart';

/// Parent dashboard card (behind the parent PIN): switches the reading homework tasks on/off
/// for the active child and picks the story level or the paper-book minutes.
class ReadingSetupCard extends ConsumerWidget {
  const ReadingSetupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final wallet = ref.watch(walletProvider);
    final ctrl = ref.read(walletProvider.notifier);
    TaskDefinition? story;
    TaskDefinition? book;
    for (final t in wallet.tasks) {
      if (t.id == ReadingTasks.storyId) story = t;
      if (t.id == ReadingTasks.bookId) book = t;
    }
    final level = story?.readingLevel ?? ReadingLevel.age5to7;
    final minutes = book?.readingMinutes ?? ReadingTasks.defaultMinutes;

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.readingSetupTitle, style: Theme.of(context).textTheme.titleMedium),
        Text(l10n.readingSetupNote, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        SwitchListTile.adaptive(
          key: const Key('readingStorySwitch'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.readingStorySwitch, style: const TextStyle(fontSize: 16)),
          value: story != null,
          onChanged: (on) => on ? ctrl.upsertTask(ReadingTasks.story(level)) : ctrl.removeTask(ReadingTasks.storyId),
        ),
        if (story != null) ...[
          Text(l10n.readingLevelLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.purpleDark)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final l in ReadingLevel.values)
              ChoiceChip(
                key: Key('readingLevel_${l.name}'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(readingLevelLabel(l10n, l), style: const TextStyle(fontSize: 15)),
                selected: l == level,
                onSelected: (_) => ctrl.upsertTask(ReadingTasks.story(l)),
              ),
          ]),
          const SizedBox(height: 8),
        ],
        SwitchListTile.adaptive(
          key: const Key('readingBookSwitch'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.readingBookSwitch, style: const TextStyle(fontSize: 16)),
          value: book != null,
          onChanged: (on) => on ? ctrl.upsertTask(ReadingTasks.book(minutes)) : ctrl.removeTask(ReadingTasks.bookId),
        ),
        if (book != null) ...[
          Text(l10n.readingMinutesLabel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.purpleDark)),
          const SizedBox(height: 4),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final m in ReadingTasks.minuteChoices)
              ChoiceChip(
                key: Key('readingMinutes_$m'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                label: Text(l10n.readingMinutesN(Fmt.digits(m, lang)), style: const TextStyle(fontSize: 15)),
                selected: m == minutes,
                onSelected: (_) => ctrl.upsertTask(ReadingTasks.book(m)),
              ),
          ]),
        ],
      ]),
    );
  }
}
