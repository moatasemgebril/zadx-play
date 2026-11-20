import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../router.dart';
import '../tasks/wallet_controller.dart';

/// Header (logo, globe, help, minutes) + bottom navigation shared by the 5 tabs.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final wallet = ref.watch(walletProvider);
    final pending = wallet.pending.length;

    final parentIcon = Badge(
      isLabelVisible: pending > 0,
      label: Text(Fmt.digits(pending, context.lang)),
      child: const Icon(Icons.shield_rounded),
    );
    final items = <(Widget, String)>[
      (const Icon(Icons.home_rounded), l10n.tabHome),
      (const Icon(Icons.sports_esports_rounded), l10n.tabGames),
      (const Icon(Icons.menu_book_rounded), l10n.tabQuran),
      (const Icon(Icons.task_alt_rounded), l10n.tabTasks),
      (parentIcon, l10n.tabParent),
    ];
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);
    final header = _Header(remaining: l10n.minutesLeft(Fmt.digits(wallet.remainingMinutes, context.lang)));

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
              destinations: [for (final (icon, label) in items) NavigationRailDestination(icon: icon, label: Text(label))],
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
          destinations: [for (final (icon, label) in items) NavigationDestination(icon: icon, label: label)],
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
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset('assets/images/zadx_logo.jpg', width: 150, height: 99, fit: BoxFit.cover, semanticLabel: 'Zad X'),
          ),
          const Spacer(),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(children: [
              _RoundIcon(icon: Icons.public_rounded, label: l10n.settingsTitle, onTap: () => context.push(Routes.settings)),
              const SizedBox(width: 8),
              _RoundIcon(icon: Icons.help_outline_rounded, label: l10n.helpTitle, onTap: () => context.push(Routes.help)),
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
  const _RoundIcon({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.16), minimumSize: const Size(48, 48)),
        icon: Icon(icon, color: Colors.white),
      );
}
