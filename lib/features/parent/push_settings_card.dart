import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../services/notifications/push_service.dart';
import '../../shared/widgets/zad_widgets.dart';

/// Parent area: opt-in to server push on THIS parent device. Hidden when push is unavailable
/// (no Firebase config, desktop/web, or a paired child device).
class PushSettingsCard extends ConsumerWidget {
  const PushSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(pushControllerProvider);
    if (status == PushStatus.unavailable) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ZadCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l10n.pushTitle, style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.pushToggle, style: const TextStyle(fontSize: 16)),
            subtitle: Text(l10n.pushSub, style: const TextStyle(fontSize: 14)),
            value: status == PushStatus.on,
            onChanged: (v) => v ? _enable(context, ref) : ref.read(pushControllerProvider.notifier).disable(),
          ),
          if (status == PushStatus.denied)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(14)),
              child: Text(l10n.pushDenied, style: const TextStyle(fontSize: 14, color: AppColors.ink)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(l10n.pushPrivacyNote, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ),
        ]),
      ),
    );
  }

  /// Explain first, then show the OS prompt (one chance on iOS, so never ask cold).
  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded, color: AppColors.purple, size: 40),
        title: Text(l10n.pushAskTitle),
        content: Text(l10n.pushAskBody, style: const TextStyle(fontSize: 16, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.pushAskLater)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.pushAskAllow)),
        ],
      ),
    );
    if (go != true) return;
    final result = await ref.read(pushControllerProvider.notifier).enable();
    if (result == PushEnableResult.failed && context.mounted) showToast(context, l10n.pushFailed);
  }
}
