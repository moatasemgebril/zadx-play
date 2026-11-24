import 'package:flutter/material.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';

/// Step-by-step guide for parents: how to limit PlayStation play time with Sony's own
/// PlayStation Family app (owner request 2026-11-24). Zad X cannot lock a PlayStation itself
/// (Sony has no public control API), so the guide is shown to every parent, on every plan.
/// Neutral wording (no religious words), so it is the same in Zad X Play and Zad X Kids.
class PsLockSteps extends StatelessWidget {
  const PsLockSteps({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final steps = [
      l10n.psStep1,
      l10n.psStep2,
      l10n.psStep3,
      l10n.psStep4,
      l10n.psStep5,
      l10n.psStep6,
      l10n.psStep7,
    ];
    return Material(
      key: const Key('psLockSteps'),
      color: const Color(0xFFE6EEFF),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.checklist_rounded, color: AppColors.psBlue),
        title: Text(l10n.psStepsTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        subtitle: Text(l10n.psStepsSub, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
        childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
        children: [
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppColors.psBlue,
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink))),
              ]),
            ),
        ],
      ),
    );
  }
}
