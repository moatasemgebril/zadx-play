import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/family_task.dart';
import '../../../services/audio/sfx_service.dart';
import '../../../shared/art/exercise_figures.dart';
import '../../../shared/widgets/zad_widgets.dart';
import '../wallet_controller.dart';
import 'praise_dialog.dart';

/// Rep counter for light exercises (push-ups, sit-ups, jumping jacks...).
/// Reaching the target sends the exercise to the parent for approval.
class ExerciseCard extends ConsumerWidget {
  const ExerciseCard({super.key, required this.task, required this.progress});
  final TaskDefinition task;
  final TaskProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final target = task.reps ?? 1;
    final count = progress.status == TaskStatus.todo ? progress.count : target;
    final title = task.title.of(lang);

    return ZadCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: task.color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
          child: AnimatedExerciseFigure(
            taskId: task.id,
            color: task.color,
            size: 64,
            reps: count,
            animate: progress.status == TaskStatus.todo,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${l10n.exReps(Fmt.digits(target, lang))} · ${l10n.minsPlus(Fmt.digits(task.rewardMinutes, lang))}',
              style: const TextStyle(fontSize: 15, color: AppColors.muted),
            ),
            const SizedBox(height: 6),
            ProgressBar(value: count / target, color: task.color, height: 8),
            const SizedBox(height: 4),
            Text(l10n.exCount(Fmt.digits(count, lang), Fmt.digits(target, lang)),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
          ]),
        ),
        const SizedBox(width: 8),
        switch (progress.status) {
          TaskStatus.todo => Semantics(
              label: l10n.exCountOne(title),
              button: true,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(62, 62),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  textStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(sfxProvider).play(Sfx.tap);
                  ref.read(walletProvider.notifier).addRep(task.id);
                  // The last rep completes the exercise (sent for approval).
                  if (task.reps != null && count + 1 >= target) {
                    showPraiseDialog(context, ref, note: l10n.toastSent(title));
                  }
                },
                child: Text(Fmt.digits('+1', lang)),
              ),
            ),
          TaskStatus.pending => _Pill(text: l10n.exPending, bg: AppColors.pendingBg, fg: AppColors.pendingText),
          TaskStatus.done => _Pill(text: l10n.completed, bg: AppColors.mintSoft, fg: AppColors.mintText),
        },
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 92),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w800)),
      );
}
