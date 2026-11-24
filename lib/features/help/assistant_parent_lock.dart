import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../parent/parent_gate.dart';

/// Child safety (BACKLOG P1, 2026-11-21 PM): the AI assistant is for parents only.
///
/// Help is reachable by the child from the main shell, so the assistant chat ([child]) is
/// shown only while the parent session is unlocked ([parentUnlockedProvider], the same
/// PIN session as the parent area). Otherwise the child sees a friendly "ask a parent"
/// card; its button opens the existing [ParentGate] PIN prompt in a sheet. When the
/// session re-locks (2 minutes idle, app in the background) the chat disappears again.
class AssistantParentLock extends ConsumerWidget {
  const AssistantParentLock({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(parentUnlockedProvider)) {
      // Typing in the assistant counts as parent activity and keeps the session open.
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => ref.read(parentUnlockedProvider.notifier).touch(),
        child: child,
      );
    }
    return const _AssistantLockedCard();
  }
}

class _AssistantLockedCard extends StatelessWidget {
  const _AssistantLockedCard();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ZadCard(
      key: const Key('assistantLockedCard'),
      color: AppColors.purpleSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        const ExcludeSemantics(child: Icon(Icons.lock_rounded, size: 44, color: AppColors.purple)),
        const SizedBox(height: 8),
        Text(l10n.assistantParentOnlyTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
        const SizedBox(height: 4),
        Text(l10n.assistantParentOnlyBody,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.ink)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('assistantAskParentButton'),
          onPressed: () => _showParentPinSheet(context),
          icon: const Icon(Icons.family_restroom_rounded),
          label: Text(l10n.askParent),
        ),
      ]),
    );
  }
}

Future<void> _showParentPinSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: const SingleChildScrollView(child: ParentGate(child: _CloseWhenUnlocked())),
      ),
    );

/// Shown by [ParentGate] once the PIN is right: closes the sheet so the parent sees the chat.
class _CloseWhenUnlocked extends StatefulWidget {
  const _CloseWhenUnlocked();

  @override
  State<_CloseWhenUnlocked> createState() => _CloseWhenUnlockedState();
}

class _CloseWhenUnlockedState extends State<_CloseWhenUnlocked> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox(height: 48);
}
