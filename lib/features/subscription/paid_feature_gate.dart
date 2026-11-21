import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/plan.dart';
import '../../router.dart';
import '../../services/billing/subscription_service.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../parent/parent_gate.dart';

/// Shows [child] when the family's plan includes [feature]; otherwise a
/// friendly, kid-safe "ask a parent" card. Free features (lock, prayer times,
/// adhan, Quran) always show [child], with or without login or purchase.
///
/// The card never shows prices or a buy button: tapping it opens
/// [showUpgradeSheet], whose plan information sits behind the parent PIN.
class PaidFeatureGate extends ConsumerWidget {
  const PaidFeatureGate({super.key, required this.feature, required this.child, this.fullScreen = false});

  final AppFeature feature;
  final Widget child;

  /// Wrap the locked card in a [Scaffold] (for whole routes such as edu games).
  final bool fullScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ent = ref.watch(entitlementProvider).valueOrNull ?? const Entitlement();
    if (hasFeature(ent, feature)) return child;
    final card = LockedFeatureCard(feature: feature);
    if (!fullScreen) return card;
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.navy, foregroundColor: Colors.white),
      body: Center(child: Padding(padding: const EdgeInsets.all(16), child: card)),
    );
  }
}

/// The kid-facing locked card: no price, no store link, just "ask a parent".
class LockedFeatureCard extends StatelessWidget {
  const LockedFeatureCard({super.key, required this.feature});
  final AppFeature feature;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ZadCard(
      color: AppColors.purpleSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const ExcludeSemantics(child: Icon(Icons.lock_rounded, size: 44, color: AppColors.purple)),
        const SizedBox(height: 8),
        Text(l10n.lockedTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
        const SizedBox(height: 4),
        Text(l10n.lockedKidBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.ink)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('askParentButton'),
          onPressed: () => showUpgradeSheet(context, feature),
          icon: const Icon(Icons.family_restroom_rounded),
          label: Text(l10n.askParent),
        ),
      ]),
    );
  }
}

/// Upgrade sheet. Its content (what the plans add, the way to the plans
/// screen) is only shown after the parent PIN ([ParentGate]); a child who
/// opens it sees only the PIN prompt.
Future<void> showUpgradeSheet(BuildContext context, AppFeature feature) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: SingleChildScrollView(
          child: ParentGate(child: _UpgradeSheetBody(feature: feature)),
        ),
      ),
    );

class _UpgradeSheetBody extends StatelessWidget {
  const _UpgradeSheetBody({required this.feature});
  final AppFeature feature;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plusOnly = !basicFeatures.contains(feature);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ExcludeSemantics(child: Icon(Icons.workspace_premium_rounded, size: 44, color: AppColors.purple)),
        const SizedBox(height: 8),
        Text(plusOnly ? l10n.upgradePlusTitle : l10n.upgradeBasicTitle,
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(l10n.upgradeBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('seePlansButton'),
          onPressed: () {
            final router = GoRouter.of(context);
            Navigator.of(context).pop();
            router.push(Routes.subscription);
          },
          child: Text(l10n.seePlans),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
      ]),
    );
  }
}
