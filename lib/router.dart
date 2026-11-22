import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/app_variant.dart';
import 'features/edu_games/letters/letters_game_screen.dart';
import 'features/edu_games/mosque/mosque_game_screen.dart';
import 'features/edu_games/prophets/prophets_game_screen.dart';
import 'features/games/games_screen.dart';
import 'features/help/help_screen.dart';
import 'features/home/home_screen.dart';
import 'features/parent/parent_screen.dart';
import 'features/quran/quran_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'data/models/plan.dart';
import 'features/subscription/paid_feature_gate.dart';
import 'features/subscription/subscription_screen.dart';
import 'features/tasks/tasks_screen.dart';

abstract class Routes {
  static const home = '/home';
  static const games = '/games';
  static const quran = '/quran';
  static const tasks = '/tasks';
  static const parent = '/parent';
  static const settings = '/settings';
  static const help = '/help';
  static const subscription = '/subscription';

  // Built-in Zad X learning games (ids match `zadGames` in data/catalog/games.dart).
  static const eduLetters = '/edu/letters';
  static const eduProphets = '/edu/prophets';
  static const eduMasjid = '/edu/masjid';
  static String eduGame(String id) => '/edu/$id';

  /// Islamic routes. Zad X Kids has no route for them at all
  /// (docs/decisions/ZADX-KIDS-VARIANT.md); a link to one goes to [home].
  static const islamicOnly = {quran, eduProphets, eduMasjid};

  /// Every route that exists only in Zad X Play: the Islamic ones + the Arabic Letters game.
  static const playOnly = {...islamicOnly, eduLetters};
}

/// The bottom-bar tabs, in order. The shell branches in [appRoutes] follow this list.
enum ShellTab {
  home(Routes.home),
  games(Routes.games),
  quran(Routes.quran),
  tasks(Routes.tasks),
  parent(Routes.parent);

  const ShellTab(this.path);
  final String path;
}

/// Tabs of [variant] (default: this build). Zad X Kids has no Quran tab.
List<ShellTab> shellTabsFor({AppVariant variant = appVariant}) => [
      ShellTab.home,
      ShellTab.games,
      if (!kIsKids && variant == AppVariant.islamic) ShellTab.quran,
      ShellTab.tasks,
      ShellTab.parent,
    ];

final _rootKey = GlobalKey<NavigatorState>();

/// Every route of [variant] (default: this build).
///
/// Zad X Play-only routes are added behind `!kIsKids`, a compile-time constant: in the Kids build
/// the Quran, prophets, mosque and Arabic Letters screens are not reachable from any route (and
/// are tree-shaken).
List<RouteBase> appRoutes({AppVariant variant = appVariant, GlobalKey<NavigatorState>? rootKey}) {
  final key = rootKey ?? _rootKey;
  return [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.games, builder: (_, __) => const GamesScreen())]),
        if (!kIsKids && variant == AppVariant.islamic)
          StatefulShellBranch(routes: [GoRoute(path: Routes.quran, builder: (_, __) => const QuranScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.tasks, builder: (_, __) => const TasksScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.parent, builder: (_, __) => const ParentScreen())]),
      ],
    ),
    GoRoute(parentNavigatorKey: key, path: Routes.settings, builder: (_, __) => const SettingsScreen()),
    GoRoute(parentNavigatorKey: key, path: Routes.help, builder: (_, __) => const HelpScreen()),
    GoRoute(parentNavigatorKey: key, path: Routes.subscription, builder: (_, __) => const SubscriptionScreen()),
    if (!kIsKids && variant == AppVariant.islamic) ...[
      GoRoute(parentNavigatorKey: key, path: Routes.eduLetters, builder: (_, __) => const PaidFeatureGate(feature: AppFeature.eduGames, fullScreen: true, child: LettersGameScreen())),
      GoRoute(parentNavigatorKey: key, path: Routes.eduProphets, builder: (_, __) => const PaidFeatureGate(feature: AppFeature.eduGames, fullScreen: true, child: ProphetsGameScreen())),
      GoRoute(parentNavigatorKey: key, path: Routes.eduMasjid, builder: (_, __) => const PaidFeatureGate(feature: AppFeature.eduGames, fullScreen: true, child: MosqueGameScreen())),
    ],
  ];
}

/// Zad X Kids: a link to a Zad X Play-only page (e.g. an old `/quran` or `/edu/letters` link) opens Home.
String? kidsRedirect(String path, {AppVariant variant = appVariant}) =>
    variant == AppVariant.kids && Routes.playOnly.any((r) => path == r || path.startsWith('$r/')) ? Routes.home : null;

GoRouter buildAppRouter({AppVariant variant = appVariant, GlobalKey<NavigatorState>? rootKey}) {
  final key = rootKey ?? _rootKey;
  return GoRouter(
    navigatorKey: key,
    initialLocation: Routes.home,
    redirect: (_, state) => kidsRedirect(state.uri.path, variant: variant),
    routes: appRoutes(variant: variant, rootKey: key),
  );
}

final appRouter = buildAppRouter();
