import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
}

final _rootKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: Routes.home,
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.games, builder: (_, __) => const GamesScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.quran, builder: (_, __) => const QuranScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.tasks, builder: (_, __) => const TasksScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.parent, builder: (_, __) => const ParentScreen())]),
      ],
    ),
    GoRoute(parentNavigatorKey: _rootKey, path: Routes.settings, builder: (_, __) => const SettingsScreen()),
    GoRoute(parentNavigatorKey: _rootKey, path: Routes.help, builder: (_, __) => const HelpScreen()),
    GoRoute(parentNavigatorKey: _rootKey, path: Routes.subscription, builder: (_, __) => const SubscriptionScreen()),
    GoRoute(parentNavigatorKey: _rootKey, path: Routes.eduLetters, builder: (_, __) => const PaidFeatureGate(feature: AppFeature.eduGames, fullScreen: true, child: LettersGameScreen())),
    GoRoute(parentNavigatorKey: _rootKey, path: Routes.eduProphets, builder: (_, __) => const PaidFeatureGate(feature: AppFeature.eduGames, fullScreen: true, child: ProphetsGameScreen())),
    GoRoute(parentNavigatorKey: _rootKey, path: Routes.eduMasjid, builder: (_, __) => const PaidFeatureGate(feature: AppFeature.eduGames, fullScreen: true, child: MosqueGameScreen())),
  ],
);
