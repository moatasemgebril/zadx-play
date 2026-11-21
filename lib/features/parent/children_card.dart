import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/child_profile.dart';
import '../../data/models/plan.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../services/billing/subscription_service.dart';
import '../../services/family/children_controller.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../prayer/prayer_providers.dart';
import '../settings/settings_controller.dart';
import '../tasks/wallet_controller.dart';

extension ChildAvatarLook on ChildAvatar {
  IconData get icon => switch (this) {
        ChildAvatar.star => Icons.star_rounded,
        ChildAvatar.moon => Icons.nightlight_round,
        ChildAvatar.sun => Icons.wb_sunny_rounded,
        ChildAvatar.rocket => Icons.rocket_launch_rounded,
        ChildAvatar.flower => Icons.local_florist_rounded,
        ChildAvatar.kitten => Icons.pets_rounded,
      };

  Color get color => switch (this) {
        ChildAvatar.star => const Color(0xFFB7791F),
        ChildAvatar.moon => AppColors.purpleDark,
        ChildAvatar.sun => const Color(0xFFC2410C),
        ChildAvatar.rocket => AppColors.psBlue,
        ChildAvatar.flower => const Color(0xFFBE185D),
        ChildAvatar.kitten => AppColors.mintText,
      };

  String label(AppLocalizations l10n) => switch (this) {
        ChildAvatar.star => l10n.avatarStar,
        ChildAvatar.moon => l10n.avatarMoon,
        ChildAvatar.sun => l10n.avatarSun,
        ChildAvatar.rocket => l10n.avatarRocket,
        ChildAvatar.flower => l10n.avatarFlower,
        ChildAvatar.kitten => l10n.avatarKitten,
      };
}

/// Nickname shown in the UI (the migrated first child may not have one yet).
String childDisplayName(ChildProfile c, AppLocalizations l10n) => c.nickname.isEmpty ? l10n.childDefaultName : c.nickname;

class ChildAvatarBadge extends StatelessWidget {
  const ChildAvatarBadge({super.key, required this.avatar, this.size = 44});
  final ChildAvatar avatar;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: avatar.color.withValues(alpha: 0.14), shape: BoxShape.circle),
        child: Icon(avatar.icon, color: avatar.color, size: size * 0.6),
      );
}

/// Parent dashboard: the family's children, a per-child summary, and
/// add / edit / remove / switch. On a paired child device it only shows whose device it is.
class ChildrenCard extends ConsumerWidget {
  const ChildrenCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final children = ref.watch(childrenProvider);
    final ent = ref.watch(entitlementProvider).valueOrNull ?? const Entitlement();
    final maxChildren = ent.limits.maxChildren;

    if (children.isBound) {
      final c = children.active;
      return ZadCard(
        child: Row(children: [
          ChildAvatarBadge(avatar: c.avatar),
          const SizedBox(width: 12),
          Expanded(
            child: Text(l10n.childDeviceBound(childDisplayName(c, l10n)),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
        ]),
      );
    }

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(l10n.childrenTitle, style: Theme.of(context).textTheme.titleMedium)),
          Text(
            l10n.childrenCount(Fmt.digits(children.children.length, lang), Fmt.digits(maxChildren, lang)),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.purpleDark),
          ),
        ]),
        const SizedBox(height: 6),
        for (final c in children.children)
          _ChildRow(child: c, active: c.id == children.activeId, canRemove: children.children.length > 1),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _add(context, ref, maxChildren),
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: Text(l10n.addChild, style: const TextStyle(fontSize: 16)),
        ),
      ]),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, int maxChildren) async {
    final l10n = context.l10n;
    final count = ref.read(childrenProvider).children.length;
    if (!canAddChild(currentCount: count, maxChildren: maxChildren)) {
      return _showUpsell(context, maxChildren);
    }
    final result = await showDialog<_ChildDraft>(context: context, builder: (_) => const _ChildEditorDialog());
    if (result == null || !context.mounted) return;
    final outcome = ref
        .read(childrenProvider.notifier)
        .add(result.nickname, result.avatar, maxChildren: maxChildren, address: result.address);
    switch (outcome) {
      case AddChildResult.added:
        showToast(context, l10n.childAdded(ChildProfile.cleanNickname(result.nickname) ?? result.nickname));
      case AddChildResult.limitReached:
        await _showUpsell(context, maxChildren);
      case AddChildResult.invalidName:
        showToast(context, l10n.childNicknameInvalid);
      case AddChildResult.notAllowed:
        break;
    }
  }

  Future<void> _showUpsell(BuildContext context, int maxChildren) async {
    final l10n = context.l10n;
    final lang = context.lang;
    final goPlans = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.workspace_premium_rounded, color: AppColors.purple, size: 40),
        title: Text(l10n.childLimitTitle),
        content: Text(l10n.childLimitBody(Fmt.digits(maxChildren, lang), Fmt.digits(planPlus.maxChildren, lang)),
            style: const TextStyle(fontSize: 16, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancelButton)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.plans)),
        ],
      ),
    );
    if (goPlans == true && context.mounted) await context.push(Routes.subscription);
  }
}

class _ChildRow extends ConsumerWidget {
  const _ChildRow({required this.child, required this.active, required this.canRemove});
  final ChildProfile child;
  final bool active;
  final bool canRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final name = childDisplayName(child, l10n);

    // Live state for the child on screen; last saved snapshot for the others.
    final WalletState wallet;
    if (active) {
      wallet = ref.watch(walletProvider);
    } else {
      final today = ref.watch(cityNowProvider.select((n) => WalletController.dayKey(n.local)));
      wallet = WalletController.restoreFrom(ref.read(sharedPrefsProvider), child.id, today);
    }

    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.purpleSoft))),
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: !active,
            selected: active,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: active ? null : () => ref.read(childrenProvider.notifier).select(child.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  ChildAvatarBadge(avatar: child.avatar),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                        if (active) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.mintSoft, borderRadius: BorderRadius.circular(10)),
                            child: Text(l10n.childActive,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.mintText)),
                          ),
                        ],
                      ]),
                      Text(
                        l10n.childSummary(
                          Fmt.digits(wallet.doneCount, lang),
                          Fmt.digits(wallet.tasks.length, lang),
                          Fmt.digits(wallet.remainingMinutes, lang),
                        ),
                        style: const TextStyle(fontSize: 15, color: AppColors.muted),
                      ),
                      if (wallet.prayerLock)
                        Text(l10n.childPrayerLocked,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.lockText)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.editChild,
          icon: const Icon(Icons.edit_rounded),
          onPressed: () => _edit(context, ref),
        ),
        if (canRemove)
          IconButton(
            tooltip: l10n.removeChild,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.lockText),
            onPressed: () => _remove(context, ref, name),
          ),
      ]),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final result = await showDialog<_ChildDraft>(
      context: context,
      builder: (_) => _ChildEditorDialog(initial: child),
    );
    if (result == null || !context.mounted) return;
    final ok = ref.read(childrenProvider.notifier).edit(
          child.id,
          nickname: result.nickname,
          avatar: result.avatar,
          address: result.address,
          clearAddress: result.address == null,
        );
    if (!ok) showToast(context, l10n.childNicknameInvalid);
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, String name) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeChildTitle(name)),
        content: Text(l10n.removeChildBody(name), style: const TextStyle(fontSize: 16, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancelButton)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.lockText),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.removeChild),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (ref.read(childrenProvider.notifier).remove(child.id)) showToast(context, l10n.childRemoved(name));
  }
}

class _ChildDraft {
  const _ChildDraft(this.nickname, this.avatar, this.address);
  final String nickname;
  final ChildAvatar avatar;
  final FormOfAddress? address;
}

class _ChildEditorDialog extends StatefulWidget {
  const _ChildEditorDialog({this.initial});
  final ChildProfile? initial;

  @override
  State<_ChildEditorDialog> createState() => _ChildEditorDialogState();
}

class _ChildEditorDialogState extends State<_ChildEditorDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial?.nickname ?? '');
  late ChildAvatar _avatar = widget.initial?.avatar ?? ChildAvatar.star;
  late FormOfAddress? _address = widget.initial?.address;
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (ChildProfile.cleanNickname(_ctrl.text) == null) return setState(() => _error = true);
    Navigator.of(context).pop(_ChildDraft(_ctrl.text, _avatar, _address));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.initial == null ? l10n.addChild : l10n.editChild),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: ChildProfile.maxNicknameLength,
            textCapitalization: TextCapitalization.words,
            keyboardType: TextInputType.name,
            autofillHints: const <String>[],
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp('[@\\n]'))],
            decoration: InputDecoration(
              labelText: l10n.childNickname,
              helperText: l10n.childNicknameHint,
              helperMaxLines: 3,
              errorText: _error ? l10n.childNicknameInvalid : null,
              errorMaxLines: 3,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(l10n.chooseAvatar, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in ChildAvatar.values)
              Semantics(
                label: a.label(l10n),
                selected: a == _avatar,
                button: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _avatar = a),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: a == _avatar ? AppColors.purple : Colors.transparent, width: 3),
                    ),
                    child: ChildAvatarBadge(avatar: a, size: 48),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          // Optional: only used to choose أحسنتَ / أحسنتِ in praise messages.
          Text(l10n.formOfAddress, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (value, label) in <(FormOfAddress?, String)>[
              (null, l10n.addressNotSet),
              (FormOfAddress.masculine, l10n.addressBoy),
              (FormOfAddress.feminine, l10n.addressGirl),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _address == value,
                onSelected: (_) => setState(() => _address = value),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancelButton)),
        FilledButton(onPressed: _submit, child: Text(l10n.saveButton)),
      ],
    );
  }
}
