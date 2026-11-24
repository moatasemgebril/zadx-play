import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_config.dart';
import '../../core/app_variant.dart';
import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/child_profile.dart';
import '../../services/family/children_controller.dart';
import '../../services/family/family_repository.dart';
import '../../services/family/pairing_service.dart';
import '../../shared/widgets/zad_widgets.dart';
import 'children_card.dart';
import 'linked_devices_list.dart';

/// Parent side: create a code to link the child's phone or a Windows PC (Zad X Guard).
class DevicesCard extends ConsumerStatefulWidget {
  const DevicesCard({super.key});

  @override
  ConsumerState<DevicesCard> createState() => _DevicesCardState();
}

class _DevicesCardState extends ConsumerState<DevicesCard> {
  PairingTarget _target = PairingTarget.phone;
  String? _childId;
  String? _code;
  bool _busy = false;

  Future<void> _create() async {
    final l10n = context.l10n;
    if (!ref.read(firebaseReadyProvider)) return showToast(context, l10n.pairOffline);
    final children = ref.read(childrenProvider);
    final child = _pairable(children)
            .where((c) => c.id == (_childId ?? ref.read(activeChildIdProvider)))
            .firstOrNull ??
        _pairable(children).first;
    setState(() => _busy = true);
    try {
      final code = await ref.read(pairingServiceProvider).createCode(_target, child);
      setState(() => _code = code);
    } catch (_) {
      if (mounted) showToast(context, l10n.pairError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Children a device can be linked to: a child paused on the Free plan cannot (the server
  /// refuses it too). The free child is never paused, so the list is never empty.
  List<ChildProfile> _pairable(ChildrenState children) {
    final pause = ref.read(childPauseProvider);
    final list = children.children.where((c) => !pause.isPaused(c.id)).toList();
    return list.isEmpty ? [children.active] : list;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final children = ref.watch(childrenProvider);
    ref.watch(childPauseProvider);
    final pairable = _pairable(children);
    final wanted = _childId ?? ref.watch(activeChildIdProvider);
    final selectedChild = pairable.where((c) => c.id == wanted).firstOrNull ?? pairable.first;
    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.pairTitle, style: Theme.of(context).textTheme.titleMedium),
        Text(l10n.pairNote, style: const TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5)),
        const SizedBox(height: 10),
        ChoiceGrid<PairingTarget>(
          // Zad X Guard for Windows computes prayer locks: not offered in Zad X Kids yet.
          items: [for (final t in PairingTarget.values) if (!kIsKids || t != PairingTarget.windows) t],
          selected: _target,
          columns: 2,
          label: (t) => switch (t) {
            PairingTarget.phone => l10n.pairPhone,
            PairingTarget.windows => l10n.computerTitle,
            PairingTarget.parent => l10n.pairParentPhone,
          },
          onSelected: (t) => setState(() {
            _target = t;
            _code = null;
          }),
        ),
        if (pairable.length > 1) ...[
          const SizedBox(height: 10),
          Text(l10n.pairForChild, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ChoiceGrid<String>(
            items: [for (final c in pairable) c.id],
            selected: selectedChild.id,
            columns: 2,
            label: (id) => childDisplayName(children.byId(id) ?? children.active, l10n),
            onSelected: (id) => setState(() {
              _childId = id;
              _code = null;
            }),
          ),
        ],
        const SizedBox(height: 10),
        if (_code != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF8FF),
              border: Border.all(color: const Color(0xFFB9A6F5), width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              Fmt.digits(_code!, 'en'),
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 8, color: AppColors.purpleDark),
            ),
          ),
          const SizedBox(height: 4),
          Text(l10n.pairValid, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          const SizedBox(height: 8),
        ],
        FilledButton(onPressed: _busy ? null : _create, child: Text(l10n.pairCreate)),
        if (_target == PairingTarget.windows) ...[
          const SizedBox(height: 14),
          Text(l10n.computerTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(l10n.computerNote, style: const TextStyle(fontSize: 15, height: 1.5)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse(AppConfig.windowsGuardDownload), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.download_rounded),
            label: Text(l10n.downloadWindows, style: const TextStyle(fontSize: 16)),
          ),
        ],
        const LinkedDevicesList(), // BACKLOG P1-3: remove a linked phone
      ]),
    );
  }
}

/// Child side (settings screen): enter the parent's code to join the family.
class JoinFamilyCard extends ConsumerStatefulWidget {
  const JoinFamilyCard({super.key});

  @override
  ConsumerState<JoinFamilyCard> createState() => _JoinFamilyCardState();
}

class _JoinFamilyCardState extends ConsumerState<JoinFamilyCard> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final l10n = context.l10n;
    if (!ref.read(firebaseReadyProvider)) return showToast(context, l10n.pairOffline);
    setState(() => _busy = true);
    try {
      await ref.read(pairingServiceProvider).redeem(_ctrl.text);
      if (mounted) showToast(context, l10n.pairDone);
      _ctrl.clear();
    } catch (_) {
      if (mounted) showToast(context, l10n.pairError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.pairEnter, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 6),
          decoration: InputDecoration(
            labelText: l10n.pairEnterHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        FilledButton(onPressed: _busy ? null : _join, child: Text(l10n.pairJoin)),
      ]),
    );
  }
}
