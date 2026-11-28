import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../router.dart';
import '../../services/family/children_controller.dart';
import '../../shared/art/zad_art.dart';
import '../parent/paused_child_screen.dart';
import '../../shared/widgets/brand_logo.dart';
import '../tasks/wallet_controller.dart';

/// Header (logo, globe, help, minutes) + bottom navigation shared by the 5 tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Free plan = one child: a paired device whose child is paused shows only a friendly
    // "ask a parent" screen (docs/decisions/FREE-ONE-CHILD.md).
    if (ref.watch(thisDevicePausedProvider)) return const PausedChildScreen();
    final l10n = context.l10n;
    final wallet = ref.watch(walletProvider);
    final pending = wallet.pending.length;

    // Original Zad X icons: quiet two-tone when idle, full colour with a
    // gentle pop (skipped with reduce-motion) when selected.
    Widget navIcon(ZadIconKind kind, {required bool selected}) {
      final icon = ZadIcon(kind, size: 28, tone: selected ? ZadIconTone.brand : ZadIconTone.muted, bounce: selected);
      if (kind != ZadIconKind.parent) return icon;
      return Badge(isLabelVisible: pending > 0, label: Text(Fmt.digits(pending, context.lang)), child: icon);
    }

    // Same order as the shell branches in router.dart (Zad X Kids has no Quran tab).
    final tabs = <(ZadIconKind, String)>[
      for (final tab in shellTabsFor())
        switch (tab) {
          ShellTab.home => (ZadIconKind.home, l10n.tabHome),
          ShellTab.games => (ZadIconKind.games, l10n.tabGames),
          ShellTab.quran => (ZadIconKind.quran, l10n.tabQuran),
          ShellTab.tasks => (ZadIconKind.tasks, l10n.tabTasks),
          ShellTab.parent => (ZadIconKind.parent, l10n.tabParent),
        },
    ];
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);
    final header = _Header(remaining: l10n.minutesLeft(wallet.remainingMinutes, Fmt.digits(wallet.remainingMinutes, context.lang)));

    return LayoutBuilder(builder: (context, constraints) {
      // Tablets, laptops, desktops and the web: side rail + centered content.
      if (constraints.maxWidth >= 900) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.white,
              indicatorColor: AppColors.purpleSoft,
              selectedLabelTextStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.purpleDark),
              unselectedLabelTextStyle: const TextStyle(fontSize: 15, color: AppColors.muted),
              destinations: [
                for (final (kind, label) in tabs)
                  NavigationRailDestination(
                    icon: navIcon(kind, selected: false),
                    selectedIcon: navIcon(kind, selected: true),
                    label: Text(label),
                  ),
              ],
            ),
            Expanded(
              child: Column(children: [
                header,
                Expanded(
                  child: Center(
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: shell),
                  ),
                ),
              ]),
            ),
          ]),
        );
      }
      return Scaffold(
        body: Column(children: [header, Expanded(child: shell)]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: go,
          destinations: [
            for (final (kind, label) in tabs)
              NavigationDestination(
                icon: navIcon(kind, selected: false),
                selectedIcon: navIcon(kind, selected: true),
                label: label,
              ),
          ],
        ),
      );
    });
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.remaining});
  final String remaining;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const BrandLogo(width: 168, height: 68),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(children: [
              _RoundIcon(kind: ZadIconKind.settings, label: l10n.settingsTitle, onTap: () => context.push(Routes.settings)),
              const SizedBox(width: 8),
              _RoundIcon(kind: ZadIconKind.help, label: l10n.helpTitle, onTap: () => context.push(Routes.help)),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(999)),
              child: Text(remaining, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.ink)),
            ),
          ]),
        ]),
        const SizedBox(height: 6),
        Text(l10n.appTagline, style: const TextStyle(color: Color(0xFFFFD866), fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.kind, required this.label, required this.onTap});
  final ZadIconKind kind;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.16), minimumSize: const Size(48, 48)),
        icon: ZadIcon(kind, tone: ZadIconTone.onDark),
      );
}
