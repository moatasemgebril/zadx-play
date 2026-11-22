import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_variant.dart';
import '../../core/l10n_ext.dart';
import '../../core/platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/games.dart';
import '../../data/models/child_profile.dart';
import '../../data/models/plan.dart';
import '../../router.dart';
import '../../services/app_lock/app_lock_service.dart';
import '../../services/billing/subscription_service.dart';
import '../../services/family/children_controller.dart';
import '../../shared/art/zad_art.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../prayer/prayer_calculator.dart';
import '../prayer/prayer_providers.dart';
import '../reading/reading_setup_card.dart';
import '../schedule/schedule_widgets.dart';
import '../settings/settings_controller.dart';
import '../settings/sound_settings_card.dart';
import '../subscription/paid_feature_gate.dart';
import '../tasks/wallet_controller.dart';
import 'children_card.dart';
import 'credits_card.dart';
import 'device_lock_card.dart';
import 'devices_card.dart';
import 'parent_gate.dart';
import 'protection_card.dart';

class ParentScreen extends ConsumerWidget {
  const ParentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ZadSceneBackground(
      scene: ZadScene.parent,
      child: ParentGate(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          PageTitle(l10n.parentTitle),
          const SizedBox(height: 12),
          const _PlanCard(),
          const SizedBox(height: 12),
          const ChildrenCard(),
          const SizedBox(height: 12),
          // Zad X Play only: Zad X Kids has no prayer tasks or prayer lock.
          if (!kIsKids) const _PrayerPauseCard(),
          const PaidFeatureGate(feature: AppFeature.tasksRewards, child: _ApprovalsCard()),
          const SizedBox(height: 12),
          const PaidFeatureGate(feature: AppFeature.tasksRewards, child: ReadingSetupCard()),
          const SizedBox(height: 12),
          const DevicesCard(),
          const SizedBox(height: 12),
          const _ConsolesCard(),
          const SizedBox(height: 12),
          const DeviceLockCard(),
          const SizedBox(height: 12),
          // Zad X Kids: study / bedtime / reading schedules replace the prayer lock.
          if (kIsKids) ...[
            const ScheduleSettingsCard(),
            const SizedBox(height: 12),
          ],
          // Settings for the parent only + prevent deleting Zad X (docs/decisions/DEVICE-PROTECTION.md).
          const ProtectionCard(),
          const SizedBox(height: 12),
          const PaidFeatureGate(feature: AppFeature.games, child: _GamesPickerCard()),
          const SizedBox(height: 12),
          const _SettingsCard(),
          const SizedBox(height: 12),
          const SoundSettingsCard(),
          const SizedBox(height: 12),
          const CreditsCard(),
        ]),
      ),
    );
  }
}

class _PlanCard extends ConsumerWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ent = ref.watch(entitlementProvider).valueOrNull ?? const Entitlement();
    final planName = ent.isFree
        ? l10n.freeName
        : ent.inTrial
            ? l10n.freeTrial
            : (ent.isPlus ? l10n.plusName : l10n.basicName);
    return ZadCard(
      color: AppColors.ink,
      child: Row(children: [
        const Icon(Icons.workspace_premium_rounded, color: AppColors.yellow, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.yourPlan, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(l10n.currentPlan(planName), style: const TextStyle(color: Colors.white, fontSize: 15)),
            // Remaining trial days are shown here, in the PIN-protected parent area only.
            if (ent.inTrial && ent.trialDaysLeft != null) ...[
              Text(
                l10n.trialDaysLeft(ent.trialDaysLeft!, Fmt.digits(ent.trialDaysLeft!, context.lang)),
                key: const Key('trialDaysLeft'),
                style: const TextStyle(color: AppColors.yellow, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              Text(l10n.trialEndsNote, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
          ]),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.ink, minimumSize: const Size(0, 46)),
          onPressed: () => context.push(Routes.subscription),
          child: Text(l10n.plans),
        ),
      ]),
    );
  }
}

class _ApprovalsCard extends ConsumerWidget {
  const _ApprovalsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final wallet = ref.watch(walletProvider);
    final children = ref.watch(childrenProvider);
    final pending = wallet.pending;

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.pendingTitle, style: Theme.of(context).textTheme.titleMedium),
        if (children.children.length > 1)
          Text(l10n.viewingChild(childDisplayName(children.active, l10n)),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.purpleDark)),
        const SizedBox(height: 6),
        if (pending.isEmpty) Text(l10n.noPending, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
        for (final t in pending)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.purpleSoft))),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.title.of(lang), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  Text(l10n.minsPlus(Fmt.digits(t.rewardMinutes, lang)), style: const TextStyle(fontSize: 15, color: AppColors.muted)),
                ]),
              ),
              TextButton(
                onPressed: () {
                  // Synced family: a paired child device cannot decide, even with the PIN (R-32).
                  final ok = ref.read(walletProvider.notifier).reject(t.id);
                  showToast(context, ok ? l10n.toastRejected(t.title.of(lang)) : l10n.approveOnParentPhone);
                },
                child: Text(l10n.reject),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
                onPressed: () {
                  final ok = ref.read(walletProvider.notifier).approve(t.id);
                  showToast(context, ok ? l10n.toastApproved(t.title.of(lang)) : l10n.approveOnParentPhone);
                },
                child: Text(l10n.approve),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Parent only (inside [ParentGate]): "excused" for the active child, today only. Shown for
/// children addressed as a girl or not set. Pauses prayer tasks and the prayer lock; no reason
/// is shown to the child or siblings, nothing goes to the family log, stars are not touched.
/// Sources: docs/decisions/PRAYER-TIMES-ACCURACY.md (Dar al-Ifta 7711, Ibn Baz 13476).
class _PrayerPauseCard extends ConsumerWidget {
  const _PrayerPauseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final children = ref.watch(childrenProvider);
    if (children.active.address == FormOfAddress.masculine) return const SizedBox.shrink();
    final paused = ref.watch(walletProvider.select((w) => w.prayerPaused));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ZadCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (children.children.length > 1)
            Text(l10n.viewingChild(childDisplayName(children.active, l10n)),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.purpleDark)),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.prayerPauseTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            subtitle: Text(l10n.prayerPauseHelp, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            value: paused,
            onChanged: (v) {
              // Synced family: only a parent device may change it (the rules refuse a child device).
              if (!ref.read(walletProvider.notifier).setPrayerPaused(v)) showToast(context, l10n.approveOnParentPhone);
            },
          ),
        ]),
      ),
    );
  }
}

/// PlayStation and Xbox/Windows have no public control API, so Zad X alerts the
/// parent and deep-links to the official parental-control app.
class _ConsolesCard extends ConsumerWidget {
  const _ConsolesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final wallet = ref.watch(walletProvider);
    final ent = ref.watch(entitlementProvider).valueOrNull ?? const Entitlement();
    // Adhan alerts and play windows between prayers: Zad X Play only.
    final prayerAlert = !kIsKids && wallet.prayerLock;
    final windows = kIsKids ? const <({Prayer after, double start, double end})>[] : playWindows(ref.watch(prayerTimesProvider));

    String label(Prayer p) => switch (p) {
          Prayer.dhuhr => l10n.afterDhuhr,
          Prayer.asr => l10n.afterAsr,
          _ => l10n.afterMaghrib,
        };

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.consolesTitle, style: Theme.of(context).textTheme.titleMedium),
        Text(l10n.consolesNote, style: const TextStyle(fontSize: 15, color: AppColors.muted, height: 1.5)),
        const SizedBox(height: 12),
        if (!hasFeature(ent, AppFeature.consoleLinks))
          FilledButton(onPressed: () => context.push(Routes.subscription), child: Text(l10n.plusName))
        else ...[
          Banner2(text: l10n.psEarned(wallet.remainingMinutes, Fmt.digits(wallet.remainingMinutes, lang)), bg: AppColors.cream, fg: AppColors.ink),
          const SizedBox(height: 12),
          _CompanionSection(
            icon: Icons.sports_esports_rounded,
            color: AppColors.psBlue,
            title: l10n.playstation,
            subtitle: l10n.psSub,
            alert: prayerAlert ? l10n.psAlertAdhan : null,
            buttonText: l10n.psOpen,
            note: l10n.psScheduleNote,
            onOpen: () => ref.read(appLockServiceProvider).openCompanionApp(CompanionApp.playStation),
          ),
          const SizedBox(height: 14),
          _CompanionSection(
            icon: Icons.desktop_windows_rounded,
            color: const Color(0xFF107C10),
            title: l10n.xboxWindows,
            subtitle: l10n.msSub,
            alert: prayerAlert ? l10n.msAlertAdhan : null,
            buttonText: l10n.msOpen,
            note: l10n.msScheduleNote,
            onOpen: () => ref.read(appLockServiceProvider).openCompanionApp(CompanionApp.microsoftFamily),
          ),
          if (windows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(l10n.psSchedule, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final w in windows)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFE6EEFF), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: Text(label(w.after), style: const TextStyle(fontSize: 16))),
                Text('${Fmt.hours(w.start, lang)} – ${Fmt.hours(w.end, lang)}',
                    textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

class _CompanionSection extends StatelessWidget {
  const _CompanionSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    required this.note,
    required this.onOpen,
    this.alert,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String buttonText;
  final String note;
  final String? alert;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(subtitle, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
            ]),
          ),
        ]),
        if (alert != null) ...[
          const SizedBox(height: 8),
          Banner2(text: alert!, bg: AppColors.lockBg, fg: AppColors.lockText),
        ],
        const SizedBox(height: 8),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: onOpen, child: Text(buttonText)),
        const SizedBox(height: 4),
        Text(note, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
      ]);
}

class _GamesPickerCard extends ConsumerWidget {
  const _GamesPickerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final s = ref.watch(settingsProvider);
    final ent = ref.watch(entitlementProvider).valueOrNull ?? const Entitlement();
    final maxGames = ent.limits.maxGames;

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(l10n.controlledGames, style: Theme.of(context).textTheme.titleMedium)),
          Text('${Fmt.digits(s.controlledGameIds.length, lang)} / ${Fmt.digits(maxGames, lang)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final g in controlledGames)
            FilterChip(
              label: Text(g.name, style: const TextStyle(fontSize: 15)),
              avatar: Icon(g.icon, size: 18, color: g.fg),
              selected: s.controlledGameIds.contains(g.id),
              onSelected: (_) {
                final ok = ref.read(settingsProvider.notifier).toggleGame(g.id, maxGames: maxGames);
                if (!ok) context.push(Routes.subscription);
              },
            ),
        ]),
        if (AppPlatform.canLockGames) ...[
        const SizedBox(height: 10),
        // iOS: Apple requires choosing apps through its own picker.
        OutlinedButton.icon(
          onPressed: () async {
            // Android: prominent disclosure first (Google Play Accessibility policy).
            await requestLockPermission(context, ref);
            await ref.read(appLockServiceProvider).pickGamesIos();
          },
          icon: const Icon(Icons.lock_person_rounded),
          label: Text(l10n.lockPermission, style: const TextStyle(fontSize: 16)),
        ),
        ],
      ]),
    );
  }
}

class _SettingsCard extends ConsumerWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.settings, style: Theme.of(context).textTheme.titleMedium),
        if (!kIsKids) _switchRow(l10n.lockAtAdhan, s.lockAtAdhan, ctrl.setLockAtAdhan),
        _switchRow(l10n.psNotifyTasks, s.notifyParentOnTasks, ctrl.setNotifyOnTasks),
        if (!kIsKids) _switchRow(l10n.psNotifyAdhan, s.notifyParentOnAdhan, ctrl.setNotifyOnAdhan),
      ]),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 16)),
        value: value,
        onChanged: onChanged,
      );
}
