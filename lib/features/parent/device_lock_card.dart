import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/app_lock/app_lock_service.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../settings/settings_controller.dart';

/// Opens the native lock permission. On Android, Google Play requires a prominent disclosure
/// (shown here, inside the parent area) before sending the user to Accessibility settings.
Future<void> requestLockPermission(BuildContext context, WidgetRef ref) async {
  final lock = ref.read(appLockServiceProvider);
  if (await lock.hasPermissions()) return;
  if (AppPlatform.isAndroid) {
    if (!context.mounted) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.lockDisclosureTitle),
        // Google Play prominent disclosure: covers every use of the service, including device
        // protection (Settings for the parent only, uninstall guard). docs/decisions/DEVICE-PROTECTION.md
        content: SingleChildScrollView(
          child: Text('${l10n.lockDisclosureBody}\n\n${l10n.protectDisclosureExtra}', style: const TextStyle(fontSize: 16)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.lockDisclosureCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.lockDisclosureAgree)),
        ],
      ),
    );
    if (ok != true) return;
  }
  await lock.requestPermissions();
}

/// Parent control for the device-wide lock (docs/decisions/DEVICE-WIDE-LOCK.md).
/// Lives inside the PIN-protected parent screen. The installed-app list never leaves the device.
class DeviceLockCard extends ConsumerWidget {
  const DeviceLockCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    final allApps = s.lockMode == LockMode.allApps;

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.deviceLockTitle, style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.deviceLockSwitch, style: const TextStyle(fontSize: 16)),
          value: allApps,
          onChanged: (v) => ctrl.setLockMode(v ? LockMode.allApps : LockMode.selectedGames),
        ),
        Text(l10n.deviceLockDesc, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
        // Plans without tasks (Free): a daily screen-time limit instead of earned minutes.
        if (!ref.watch(lockTasksEnabledProvider)) ...[
          const SizedBox(height: 8),
          Text(l10n.deviceLockDailyLimit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in const [30, 60, 90, 120, 180])
              ChoiceChip(
                label: Text(l10n.deviceLockMinutes(Fmt.digits(m, lang)), style: const TextStyle(fontSize: 15)),
                selected: s.dailyLimitMinutes == m,
                onSelected: (_) => ctrl.setDailyLimitMinutes(m),
              ),
          ]),
        ],
        if (allApps) ...[
          const SizedBox(height: 8),
          Banner2(
              text: AppPlatform.isAndroid && s.lockDeviceSettings ? l10n.deviceLockAlwaysOpenProtected : l10n.deviceLockAlwaysOpen,
              bg: AppColors.mintSoft, fg: AppColors.mintText, icon: Icons.phone_rounded),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.deviceLockMessaging, style: const TextStyle(fontSize: 16)),
            value: s.allowMessaging,
            onChanged: ctrl.setAllowMessaging,
          ),
          if (AppPlatform.isAndroid) ...[
            Text(l10n.deviceLockAllowedCount(Fmt.digits(s.allowedApps.length, lang)),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.purpleDark)),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _showAllowList(context, ref),
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: Text(l10n.deviceLockChooseApps, style: const TextStyle(fontSize: 16)),
            ),
            TextButton(
              onPressed: () => _showAlwaysAllowed(context, ref, s.allowMessaging),
              child: Text(l10n.deviceLockShowAlways, style: const TextStyle(fontSize: 15)),
            ),
          ],
          if (AppPlatform.isIOS) ...[
            OutlinedButton.icon(
              onPressed: () async {
                await requestLockPermission(context, ref);
                await ref.read(appLockServiceProvider).pickAllowedAppsIos();
              },
              icon: const Icon(Icons.playlist_add_check_rounded),
              label: Text(l10n.deviceLockChooseApps, style: const TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 4),
            Text(l10n.deviceLockIosNote, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.deviceLockPcBrowsers, style: const TextStyle(fontSize: 16)),
            value: s.pcAllowBrowsers,
            onChanged: ctrl.setPcAllowBrowsers,
          ),
          Text(l10n.deviceLockMinutesNote, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
        ],
      ]),
    );
  }

  Future<void> _showAlwaysAllowed(BuildContext context, WidgetRef ref, bool allowMessaging) async {
    final apps = await ref.read(appLockServiceProvider).alwaysAllowedApps(allowMessaging: allowMessaging);
    if (!context.mounted) return;
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deviceLockShowAlways),
        content: SizedBox(
          width: double.maxFinite,
          child: apps.isEmpty
              ? Text(l10n.deviceLockNoApps)
              : ListView(shrinkWrap: true, children: [
                  for (final a in apps)
                    ListTile(dense: true, leading: const Icon(Icons.lock_open_rounded), title: Text(a.label)),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.deviceLockDone))],
      ),
    );
  }

  Future<void> _showAllowList(BuildContext context, WidgetRef ref) async {
    final apps = await ref.read(appLockServiceProvider).listApps();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AllowListSheet(apps: apps),
    );
  }
}

class _AllowListSheet extends ConsumerWidget {
  const _AllowListSheet({required this.apps});

  final List<InstalledApp> apps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final allowed = ref.watch(settingsProvider.select((s) => s.allowedApps));
    final ctrl = ref.read(settingsProvider.notifier);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.deviceLockChooseApps, style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: apps.isEmpty
                ? Center(child: Text(l10n.deviceLockNoApps))
                : ListView.builder(
                    itemCount: apps.length,
                    itemBuilder: (_, i) {
                      final a = apps[i];
                      return CheckboxListTile(
                        title: Text(a.label, style: const TextStyle(fontSize: 16)),
                        value: allowed.contains(a.package),
                        onChanged: (v) => ctrl.setAppAllowed(a.package, v ?? false),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(onPressed: () => Navigator.pop(context), child: Text(l10n.deviceLockDone)),
          ),
        ]),
      ),
    );
  }
}
