import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/family_task.dart';
import '../../shared/widgets/zad_widgets.dart';
import 'wallet_controller.dart';
import 'widgets/exercise_card.dart';

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final wallet = ref.watch(walletProvider);
    final regular = wallet.tasks.where((t) => !t.isExercise).toList();
    final exercises = wallet.tasks.where((t) => t.isExercise).toList();

    return PatternBackground(
      tint: AppColors.pageTints['tasks']!,
      seed: 4,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        PageTitle(l10n.tasks, subtitle: l10n.tasksNote),
        const SizedBox(height: 12),
        for (final t in regular) ...[
          _TaskCard(task: t, progress: wallet.progressOf(t.id)),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Text(l10n.exTitle, style: AppTheme.display(24)),
        Text(l10n.exNote, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        const SizedBox(height: 10),
        for (final t in exercises) ...[
          ExerciseCard(task: t, progress: wallet.progressOf(t.id)),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task, required this.progress});
  final TaskDefinition task;
  final TaskProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;

    return ZadCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 16,
            height: 16,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: task.color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.title.of(lang), style: Theme.of(context).textTheme.titleMedium),
              Text(task.subtitle.of(lang), style: const TextStyle(fontSize: 15, color: AppColors.muted)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: task.required ? AppColors.purple : AppColors.mintSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                task.required ? l10n.mustDo : l10n.bonus,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: task.required ? Colors.white : AppColors.mintText),
              ),
            ),
            const SizedBox(height: 4),
            Text(l10n.minsPlus(Fmt.digits(task.rewardMinutes, lang)),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
          ]),
        ]),
        const SizedBox(height: 10),
        switch (progress.status) {
          TaskStatus.todo => OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 50),
                side: const BorderSide(color: AppColors.purple, width: 2),
                foregroundColor: AppColors.purpleDark,
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                ref.read(walletProvider.notifier).submit(task.id);
                showToast(context, l10n.toastSent(task.title.of(lang)));
              },
              child: Text(l10n.doneBtn),
            ),
          TaskStatus.pending => Banner2(text: l10n.pendingApproval, bg: AppColors.pendingBg, fg: AppColors.pendingText),
          TaskStatus.done => Banner2(text: l10n.completed, bg: AppColors.mintSoft, fg: AppColors.mintText, icon: Icons.check_rounded),
        },
      ]),
    );
  }
}
