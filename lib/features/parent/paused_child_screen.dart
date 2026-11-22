import 'package:flutter/material.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/plan.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../subscription/paid_feature_gate.dart';

/// Shown on a paired child device whose child is paused on the Free plan (one child only,
/// owner decision 2026-11-21, docs/decisions/FREE-ONE-CHILD.md).
///
/// Kid-safe: a friendly "ask a parent" message, no price and no store link. The button opens
/// [showUpgradeSheet], whose plan information sits behind the parent PIN. The child's progress
/// is kept and comes back by itself when the family subscribes.
class PausedChildScreen extends StatelessWidget {
  const PausedChildScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: const Key('pausedChildScreen'),
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ZadCard(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const ExcludeSemantics(child: Icon(Icons.bedtime_rounded, size: 56, color: AppColors.purple)),
                  const SizedBox(height: 10),
                  Semantics(
                    header: true,
                    child: Text(l10n.pausedKidTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.pausedKidBody,
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, height: 1.5, color: AppColors.ink)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('pausedAskParentButton'),
                    onPressed: () => showUpgradeSheet(context, AppFeature.multipleChildren),
                    icon: const Icon(Icons.family_restroom_rounded),
                    label: Text(l10n.askParent),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
