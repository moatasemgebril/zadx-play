import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/core/utils/formatters.dart';
import 'package:zadx/features/edu_games/edu_game_hooks.dart';
import 'package:zadx/features/edu_games/letters/letters_game_screen.dart';
import 'package:zadx/features/edu_games/mosque/mosque_game_screen.dart';
import 'package:zadx/features/edu_games/prophets/prophets_game_screen.dart';
import 'package:zadx/features/edu_games/widgets/edu_widgets.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';

// Accessibility of the three learning games: every answer and button has a
// screen-reader label and a tap action, tap targets are at least 48 × 48 dp,
// right / try-again states show an icon and text (not colour alone), and the
// "Exit game" button always leaves the game with no confirmation.

const _home = Key('hub');

Future<void> _pumpGame(WidgetTester tester, Widget game, String lang) async {
  tester.view.physicalSize = const Size(1080, 3600); // 360 dp wide phone, tall enough to show a whole question
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'settings.language': lang});
  final prefs = await SharedPreferences.getInstance();
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      // No sounds or haptics in tests.
      eduGameHooksProvider.overrideWithValue(const EduGameHooks()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(key: _home, body: SizedBox.expand()),
    ),
  ));
  // Open the game on top of a page, like the games hub does.
  navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => game));
  await tester.pumpAndSettle();
}

/// The Material button (plain or `.icon`) that shows [text].
Finder _button(String text) =>
    find.ancestor(of: find.text(text), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(EduGameScaffold)));

void _expectTapTarget(WidgetTester tester, Finder finder, {String? reason}) {
  final size = tester.getSize(finder);
  expect(size.width, greaterThanOrEqualTo(48), reason: 'width of $reason');
  expect(size.height, greaterThanOrEqualTo(48), reason: 'height of $reason');
}

/// Every answer button is a labelled, tappable button of at least 48 × 48 dp.
void _expectAccessibleChoices(WidgetTester tester, {required int atLeast}) {
  final choices = find.byType(BigChoiceButton);
  expect(choices, findsAtLeastNWidgets(atLeast));
  for (var i = 0; i < choices.evaluate().length; i++) {
    final choice = choices.at(i);
    _expectTapTarget(tester, choice, reason: 'choice $i');
    final node = tester.getSemantics(choice);
    expect(node.label.trim(), isNotEmpty, reason: 'choice $i has no screen-reader label');
    expect(node, containsSemantics(isButton: true, hasTapAction: true), reason: 'choice $i');
  }
}

/// The exit button is labelled, big enough, and leaves the game at once.
Future<void> _expectExitWorks(WidgetTester tester) async {
  final l10n = _l10n(tester);
  final exit = find.byTooltip(l10n.eduExitGame);
  expect(exit, findsOneWidget);
  _expectTapTarget(tester, find.byKey(const Key('eduExitGame')), reason: 'exit button');
  await tester.tap(exit);
  await tester.pumpAndSettle();
  expect(find.byType(EduGameScaffold), findsNothing, reason: 'exit must not ask for confirmation');
  expect(find.byKey(_home), findsOneWidget);
}

void main() {
  for (final lang in ['ar', 'en']) {
    group('[$lang]', () {
      testWidgets('Quran Letters: levels and answers are labelled, tappable and ≥ 48 dp', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpGame(tester, const LettersGameScreen(), lang);
        final l10n = _l10n(tester);

        final level1 = l10n.eduLevelN(Fmt.digits(1, lang));
        final card = find.bySemanticsLabel(RegExp(RegExp.escape(level1)));
        expect(card, findsOneWidget);
        expect(tester.getSemantics(card), containsSemantics(isButton: true, hasTapAction: true));
        _expectTapTarget(tester, card, reason: 'level 1 card');

        await tester.tap(find.text(level1));
        await tester.pumpAndSettle();
        _expectAccessibleChoices(tester, atLeast: 3);
        await _expectExitWorks(tester);
        semantics.dispose();
      });

      testWidgets('Heroes of the Prophets: start button and answers are labelled and ≥ 48 dp', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpGame(tester, const ProphetsGameScreen(), lang);
        final l10n = _l10n(tester);

        final play = _button(l10n.play);
        _expectTapTarget(tester, play, reason: 'play button');
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(l10n.play))), findsWidgets);

        await tester.tap(play);
        await tester.pumpAndSettle();
        _expectAccessibleChoices(tester, atLeast: 2);
        await _expectExitWorks(tester);
        semantics.dispose();
      });

      testWidgets('Build Your Mosque: buttons and part chips are labelled and ≥ 48 dp', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpGame(tester, const MosqueGameScreen(), lang);
        final l10n = _l10n(tester);

        // No stars yet: the build button is shown (disabled) with the reason in text.
        final build = _button(l10n.mosqueBuild);
        _expectTapTarget(tester, build, reason: 'build button');
        expect(find.bySemanticsLabel(RegExp(RegExp.escape(l10n.mosqueBuild))), findsWidgets);
        for (final game in [l10n.zadGameLetters, l10n.zadGameProphets]) {
          _expectTapTarget(tester, _button(game), reason: game);
          expect(find.bySemanticsLabel(RegExp(RegExp.escape(game))), findsWidgets);
        }
        final chips = find.byWidgetPredicate((w) => w is InkWell && w.borderRadius == BorderRadius.circular(999));
        expect(chips, findsWidgets);
        for (var i = 0; i < chips.evaluate().length; i++) {
          expect(tester.getSize(chips.at(i)).height, greaterThanOrEqualTo(48), reason: 'part chip $i');
        }
        await _expectExitWorks(tester);
        semantics.dispose();
      });
    });
  }

  group('answer states do not rely on colour alone', () {
    Future<AppLocalizations> pumpChoice(WidgetTester tester, ChoiceLook look) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: BigChoiceButton(look: look, onTap: () {}, semanticLabel: 'باء', minHeight: 20, child: const Text('ب')),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return AppLocalizations.of(tester.element(find.byType(BigChoiceButton)));
    }

    testWidgets('a correct answer shows a tick and says "correct"', (tester) async {
      final semantics = tester.ensureSemantics();
      final l10n = await pumpChoice(tester, ChoiceLook.correct);
      expect(find.byKey(const Key('choiceCorrectMark')), findsOneWidget);
      expect(find.byKey(const Key('choiceTriedMark')), findsNothing);
      expect(tester.getSemantics(find.byType(BigChoiceButton)).label, l10n.eduChoiceCorrect('باء'));
      semantics.dispose();
    });

    testWidgets('a tried answer shows a try-again mark and says so', (tester) async {
      final semantics = tester.ensureSemantics();
      final l10n = await pumpChoice(tester, ChoiceLook.tried);
      expect(find.byKey(const Key('choiceTriedMark')), findsOneWidget);
      expect(find.byKey(const Key('choiceCorrectMark')), findsNothing);
      expect(tester.getSemantics(find.byType(BigChoiceButton)).label, l10n.eduChoiceTried('باء'));
      semantics.dispose();
    });

    testWidgets('an idle answer is just its name, and a small minHeight is raised to 48 dp', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpChoice(tester, ChoiceLook.idle);
      expect(tester.getSemantics(find.byType(BigChoiceButton)).label, 'باء');
      expect(tester.getSize(find.byType(BigChoiceButton)).height, greaterThanOrEqualTo(48));
      semantics.dispose();
    });

    for (final positive in [true, false]) {
      testWidgets('feedback line shows an icon with the ${positive ? 'well-done' : 'try-again'} text', (tester) async {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: FeedbackLine(text: positive ? 'WELL' : 'AGAIN', positive: positive)),
        ));
        await tester.pumpAndSettle();
        expect(find.text(positive ? 'WELL' : 'AGAIN'), findsOneWidget);
        expect(find.byKey(Key(positive ? 'feedbackCorrectIcon' : 'feedbackTryAgainIcon')), findsOneWidget);
      });
    }
  });
}
