import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/app_lock/app_lock_service.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../settings/settings_controller.dart';
import 'parent_gate.dart';

/// Opens the phone's Settings to the parent for [parentWindowMinutes] after the PIN, then shows
/// [screen] (`settings | accessibility | notifications | appDetails | usageAccess | wifi`).
/// Every Zad X flow that sends the parent to Settings goes through here (owner decision 2026-11-21).
Future<bool> openSettingsForParent(BuildContext context, WidgetRef ref, {String screen = 'settings'}) async {
  if (!AppPlatform.isAndroid) return false;
  if (!await confirmParentPin(context, ref)) return false;
  final lock = ref.read(appLockServiceProvider);
  await lock.openParentWindow();
  return lock.openDeviceSettings(screen);
}

/// Parent controls for device protection (docs/decisions/DEVICE-PROTECTION.md):
/// "Lock Settings for the child" (on by default) and "Prevent deleting Zad X".
/// Lives inside the PIN-protected parent screen; turning a protection off asks for the PIN again.
class ProtectionCard extends ConsumerStatefulWidget {
  const ProtectionCard({super.key});

  @override
  ConsumerState<ProtectionCard> createState() => _ProtectionCardState();
}

class _ProtectionCardState extends ConsumerState<ProtectionCard> with WidgetsBindingObserver {
  bool _adminActive = false;
  int _windowSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Back from Android's activation screen or from Settings: re-read the state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!AppPlatform.isAndroid) return;
    final lock = ref.read(appLockServiceProvider);
    try {
      final admin = await lock.deviceAdminActive();
      final seconds = await lock.parentWindowSeconds();
      if (!mounted) return;
      setState(() {
        _adminActive = admin;
        _windowSeconds = seconds;
      });
    } catch (_) {
      // Native side missing (tests, desktop): keep defaults.
    }
  }

  Future<void> _setSettingsLock(bool on) async {
    // Turning protection off needs the PIN again; turning it on never does.
    if (!on && !await confirmParentPin(context, ref)) return;
    ref.read(settingsProvider.notifier).setLockDeviceSettings(on);
    if (on) await ref.read(appLockServiceProvider).closeParentWindow();
    await _refresh();
  }

  Future<void> _setPreventUninstall(bool on) async {
    final lock = ref.read(appLockServiceProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    if (!await confirmParentPin(context, ref)) return;
    if (!on) {
      ctrl.setPreventUninstall(false);
      if (AppPlatform.isAndroid) await lock.removeDeviceAdmin();
      await _refresh();
      return;
    }
    ctrl.setPreventUninstall(true);
    if (AppPlatform.isAndroid && mounted) await _activateAdmin(askPin: false);
  }

  /// Google Play: prominent disclosure before Android's Device Admin screen.
  Future<void> _activateAdmin({bool askPin = true}) async {
    if (askPin && !await confirmParentPin(context, ref)) return;
    if (!mounted) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.protectAdminDisclosureTitle),
        content: SingleChildScrollView(
          child: Text(l10n.protectAdminDisclosureBody, style: const TextStyle(fontSize: 16)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.lockDisclosureCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.lockDisclosureAgree)),
        ],
      ),
    );
    if (ok != true) return;
    final lock = ref.read(appLockServiceProvider);
    // The activation screen is part of Android Settings, so open the parent window first.
    await lock.openParentWindow();
    await lock.requestDeviceAdmin(l10n.protectAdminExplanation);
  }

  Future<void> _openSettings() async {
    await openSettingsForParent(context, ref);
    await _refresh();
  }

  Future<void> _lockNow() async {
    await ref.read(appLockServiceProvider).closeParentWindow();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.canLockGames) return const SizedBox.shrink();
    final l10n = context.l10n;
    final lang = context.lang;
    final s = ref.watch(settingsProvider);
    final android = AppPlatform.isAndroid;
    const small = TextStyle(fontSize: 14, color: AppColors.muted);

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.shield_rounded, color: AppColors.purple),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.protectTitle, style: Theme.of(context).textTheme.titleMedium)),
        ]),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.protectSettingsSwitch, style: const TextStyle(fontSize: 16)),
          value: s.lockDeviceSettings,
          onChanged: _setSettingsLock,
        ),
        Text(android ? l10n.protectSettingsDesc : l10n.protectSettingsDescIos, style: small),
        if (android && s.lockDeviceSettings) ...[
          const SizedBox(height: 8),
          if (_windowSeconds > 0) ...[
            Banner2(
              text: l10n.protectWindowOpen((_windowSeconds / 60).ceil(), Fmt.digits((_windowSeconds / 60).ceil(), lang)),
              bg: AppColors.pendingBg,
              fg: AppColors.pendingText,
              icon: Icons.lock_open_rounded,
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _lockNow,
              icon: const Icon(Icons.lock_rounded),
              label: Text(l10n.protectLockNow, style: const TextStyle(fontSize: 16)),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded),
              label: Text(l10n.protectOpenSettings, style: const TextStyle(fontSize: 16)),
            ),
        ],
        const Divider(height: 24),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.protectUninstallSwitch, style: const TextStyle(fontSize: 16)),
          value: s.preventUninstall,
          onChanged: _setPreventUninstall,
        ),
        Text(android ? l10n.protectUninstallDesc : l10n.protectUninstallDescIos, style: small),
        if (android && s.preventUninstall) ...[
          const SizedBox(height: 6),
          if (_adminActive)
            Banner2(
              text: l10n.protectAdminActive,
              bg: AppColors.mintSoft,
              fg: AppColors.mintText,
              icon: Icons.verified_user_rounded,
            )
          else
            InkWell(
              onTap: _activateAdmin,
              borderRadius: BorderRadius.circular(16),
              child: Banner2(
                text: l10n.protectAdminInactive,
                bg: AppColors.lockBg,
                fg: AppColors.lockText,
                icon: Icons.warning_amber_rounded,
              ),
            ),
        ],
        const SizedBox(height: 10),
        Text(l10n.protectTamperNote, style: small),
      ]),
    );
  }
}
