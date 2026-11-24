import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';
import '../../services/family/children_controller.dart';
import '../../services/family/family_repository.dart';
import '../../shared/widgets/zad_widgets.dart';
import 'children_card.dart';

/// The phones linked to this family (members of the family doc). Empty for a local-only family.
final linkedDevicesProvider = StreamProvider.autoDispose<List<LinkedDevice>>(
  (ref) => ref.watch(familyRepositoryProvider).watchLinkedDevices(),
);

/// Parent area → Link devices: the linked phones, each with "Remove device" (BACKLOG P1-3), e.g. a
/// lost phone or a device linked by mistake. The server (`removeLinkedDevice`) decides who may
/// remove whom; this phone is never offered for removal here.
class LinkedDevicesList extends ConsumerWidget {
  const LinkedDevicesList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A paired child device never manages devices (the server refuses it too).
    if (ref.watch(childrenProvider.select((s) => s.isBound))) return const SizedBox.shrink();
    final devices = ref.watch(linkedDevicesProvider).valueOrNull ?? const <LinkedDevice>[];
    if (devices.length < 2) return const SizedBox.shrink(); // only this phone: nothing to manage
    final l10n = context.l10n;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      Text(l10n.linkedDevicesTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      for (final d in devices) _DeviceRow(device: d),
    ]);
  }
}

class _DeviceRow extends ConsumerStatefulWidget {
  const _DeviceRow({required this.device});
  final LinkedDevice device;

  @override
  ConsumerState<_DeviceRow> createState() => _DeviceRowState();
}

class _DeviceRowState extends ConsumerState<_DeviceRow> {
  bool _busy = false;

  String _label(AppLocalizations l10n) {
    final d = widget.device;
    if (d.isThisDevice) return l10n.linkedDeviceThis;
    if (d.isParent) return l10n.linkedDeviceParent;
    final children = ref.watch(childrenProvider);
    final child = children.byId(d.childId!);
    return l10n.linkedDeviceChild(child == null ? l10n.childDefaultName : childDisplayName(child, l10n));
  }

  Future<void> _remove() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.phonelink_erase_rounded, color: AppColors.purple, size: 40),
        title: Text(l10n.deviceRemoveTitle),
        content: Text(l10n.deviceRemoveBody, style: const TextStyle(fontSize: 16, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.deviceRemoveConfirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      await ref.read(familyRepositoryProvider).removeLinkedDevice(widget.device.uid);
      message = l10n.deviceRemoved;
    } on DeviceRemovalRejected catch (e) {
      message = e.isLastParent ? l10n.deviceRemoveLastParent : l10n.deviceRemoveError;
    } catch (_) {
      message = l10n.deviceRemoveError;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final d = widget.device;
    final uid = d.uid;
    // Last characters of the device id tell two phones of the same child apart (not personal data).
    final tag = uid.length > 4 ? uid.substring(uid.length - 4) : uid;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(d.isParent ? Icons.admin_panel_settings_rounded : Icons.smartphone_rounded, color: AppColors.purpleDark),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: _label(l10n), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              TextSpan(text: '  ·  $tag', style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ]),
          ),
        ),
        if (!d.isThisDevice)
          TextButton(
            key: ValueKey('removeDevice-$uid'),
            onPressed: _busy ? null : _remove,
            child: Text(l10n.deviceRemove),
          ),
      ]),
    );
  }
}
