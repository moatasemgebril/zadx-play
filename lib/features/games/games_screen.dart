import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_ext.dart';
import '../../core/platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/games.dart';
import '../../data/models/family_task.dart';
import '../../data/models/game.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../../services/app_lock/app_lock_service.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../settings/settings_controller.dart';
import '../tasks/wallet_controller.dart';

class GamesScreen extends ConsumerWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final wallet = ref.watch(walletProvider);
    final enabledIds = ref.watch(settingsProvider.select((s) => s.controlledGameIds));
    final games = controlledGames.where((g) => enabledIds.contains(g.id)).toList();

    return PatternBackground(
      tint: AppColors.pageTints['games']!,
      seed: 2,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        _GamesHero(title: l10n.gamesHeroTitle, sub: l10n.gamesHeroSub),
        const SizedBox(height: 16),
        Text(l10n.zadGames, style: Theme.of(context).textTheme.titleMedium),
        Text(l10n.zadGamesNote, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        const SizedBox(height: 10),
        Row(children: [
          for (final g in zadGames) ...[
            Expanded(child: _ZadGameTile(game: g, title: _zadTitle(l10n, g.id))),
            if (g != zadGames.last) const SizedBox(width: 10),
          ],
        ]),
        const SizedBox(height: 18),
        Text(l10n.deviceGames, style: Theme.of(context).textTheme.titleMedium),
        Text(l10n.deviceGamesNote, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        const SizedBox(height: 10),
        _LockBanner(wallet: wallet),
        if (wallet.prayerLock) ...[const SizedBox(height: 10), const _PrayerLockCard()],
        const SizedBox(height: 10),
        Text(l10n.gamesCount(Fmt.digits(games.length, lang)),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.62,
          children: [for (final g in games) _GameTile(game: g, unlocked: wallet.gamesUnlocked)],
        ),
      ]),
    );
  }

  String _zadTitle(AppLocalizations l10n, String id) => switch (id) {
        'letters' => l10n.zadGameLetters,
        'prophets' => l10n.zadGameProphets,
        _ => l10n.zadGameMasjid,
      };
}

class _GamesHero extends StatelessWidget {
  const _GamesHero({required this.title, required this.sub});
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) => Container(
        height: 130,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(24)),
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          const PositionedDirectional(
            end: -8,
            bottom: -18,
            child: RotationTransition(
              turns: AlwaysStoppedAnimation(-0.03),
              child: Icon(Icons.sports_esports_rounded, size: 130, color: AppColors.yellow),
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(title, style: AppTheme.display(30, color: Colors.white)),
            SizedBox(width: 200, child: Text(sub, style: const TextStyle(color: Colors.white, fontSize: 16))),
          ]),
        ]),
      );
}

class _ZadGameTile extends StatelessWidget {
  const _ZadGameTile({required this.game, required this.title});
  final ZadGame game;
  final String title;

  @override
  Widget build(BuildContext context) => ZadCard(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Container(
            height: 70,
            decoration: BoxDecoration(color: game.bg, borderRadius: BorderRadius.circular(14)),
            child: Center(child: Icon(game.icon, size: 40, color: game.fg)),
          ),
          const SizedBox(height: 6),
          SizedBox(height: 40, child: Center(child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)))),
          FilledButton(onPressed: () => context.push(Routes.eduGame(game.id)), child: Text(context.l10n.play)),
        ]),
      );
}

class _LockBanner extends StatelessWidget {
  const _LockBanner({required this.wallet});
  final WalletState wallet;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (wallet.gamesUnlocked) {
      return Banner2(
        text: l10n.gamesOpen(Fmt.digits(wallet.remainingMinutes, context.lang)),
        bg: AppColors.mintSoft,
        fg: AppColors.mintText,
        icon: Icons.lock_open_rounded,
      );
    }
    final text = switch (wallet.lockReason) {
      LockReason.prayer => l10n.lockPrayer,
      LockReason.requiredTasks => l10n.lockRequired,
      _ => l10n.lockTime,
    };
    return Banner2(text: text, bg: AppColors.lockBg, fg: AppColors.lockText, icon: Icons.lock_rounded);
  }
}

class _PrayerLockCard extends ConsumerWidget {
  const _PrayerLockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final wallet = ref.watch(walletProvider);
    final prayerName = wallet.lockedPrayer == null ? '' : l10n.prayerName(wallet.lockedPrayer!);
    final submitted = wallet.pending.any((t) => t.kind == TaskKind.prayer);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(24)),
      child: Column(children: [
        const Icon(Icons.nightlight_round, color: Colors.white, size: 38),
        const SizedBox(height: 6),
        Text(l10n.prayerNow(prayerName), textAlign: TextAlign.center, style: AppTheme.display(24, color: Colors.white)),
        Text(l10n.prayerSub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
        const SizedBox(height: 12),
        if (!submitted)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.yellow, foregroundColor: AppColors.ink),
            onPressed: () => ref.read(walletProvider.notifier).markPrayed(),
            child: Text(l10n.iPrayed),
          )
        else
          Text(l10n.waitParent, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _GameTile extends ConsumerWidget {
  const _GameTile({required this.game, required this.unlocked});
  final ControlledGame game;
  final bool unlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ZadCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(color: game.bg, borderRadius: BorderRadius.circular(16)),
          child: Icon(game.icon, color: game.fg, size: 32),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Column(children: [
            Text(game.name, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            Text(game.tag.of(context.lang), textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ]),
        ),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 46),
              backgroundColor: unlocked ? AppColors.purple : const Color(0xFFEDEAF5),
              foregroundColor: unlocked ? Colors.white : AppColors.muted,
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            onPressed: unlocked && AppPlatform.canLockGames
                ? () async {
                    // Minutes are deducted per minute of real play by the native layer
                    // (session_minute events), not up front.
                    final ok = await ref.read(appLockServiceProvider).launchGame(game);
                    if (context.mounted && ok) showToast(context, l10n.toastOpened(game.name));
                  }
                : null,
            child: Text(!unlocked ? l10n.locked : (AppPlatform.canLockGames ? l10n.play : l10n.playOnDevice)),
          ),
        ),
      ]),
    );
  }
}
