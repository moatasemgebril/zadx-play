// Zad X Kids artwork guard rails (owner decision 2026-11-22: Zad X Kids targets the US / Europe).
//
// Rules (docs/decisions/ZADX-KIDS-VARIANT.md, "Artwork rules for Zad X Kids"):
//   1. no Arabic script in any artwork (scenes, painters, icons, brand / splash widgets);
//   2. no mosque, dome, minaret, crescent, lantern, Kaaba, prayer mat or Islamic star pattern;
//   3. English is the default UI language;
//   4. no Arabic Letters game.
//
// Runs twice in CI:
//   flutter test                                                       (Zad X Play build: the Kids
//                                                                       painters are checked with
//                                                                       explicit parameters)
//   flutter test --dart-define=ZADX_VARIANT=kids test/kids_artwork_test.dart   (the real Kids
//                                                                       build constants + rendering)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/core/app_variant.dart';
import 'package:zadx/data/catalog/games.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/router.dart';
import 'package:zadx/shared/art/scenes/games_scene.dart';
import 'package:zadx/shared/art/scenes/home_scene.dart';
import 'package:zadx/shared/art/scenes/night_scene.dart';
import 'package:zadx/shared/art/scenes/parent_scene.dart';
import 'package:zadx/shared/art/scenes/prayer_sky.dart';
import 'package:zadx/shared/art/scenes/tasks_scene.dart';
import 'package:zadx/shared/art/zad_art.dart';
import 'package:zadx/shared/widgets/brand_logo.dart';
import 'package:zadx/variant/kids_localizations.dart';

/// Arabic script blocks: Arabic, Arabic Supplement, Arabic Extended-A, Presentation Forms A and B.
final arabicScript = RegExp('[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');

/// Source of every artwork / brand widget the Kids build can show. The whole file is scanned
/// (string literals and comments), so Arabic text for Zad X Play must live elsewhere
/// (e.g. lib/core/app_config.dart or the ARB files).
const kidsArtworkSources = [
  'lib/shared/art',
  'lib/shared/widgets',
  'lib/features/splash',
  'lib/features/schedule/schedule_widgets.dart',
];

List<File> _dartFiles(String path) {
  if (FileSystemEntity.isFileSync(path)) return [File(path)];
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return [
    for (final e in dir.listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e,
  ]..sort((a, b) => a.path.compareTo(b.path));
}

List<String> _paths(List<RouteBase> routes) => [
      for (final r in routes) ...[
        if (r is GoRoute) r.path,
        ..._paths(r.routes),
      ],
    ];

const _anim = AlwaysStoppedAnimation<double>(0.37);

/// Every painter of the Kids artwork, built with the Kids parameters.
List<(String, CustomPainter)> kidsPainters() => [
      ('home', const HomeStaticPainter(withMosque: false)),
      ('home motion', HomeMotionPainter(_anim)),
      ('games', const GamesStaticPainter()),
      ('games motion', GamesMotionPainter(_anim)),
      ('tasks', const TasksStaticPainter()),
      ('tasks motion', TasksMotionPainter(_anim, blooms: 5)),
      ('night', const NightStaticPainter(religiousMotifs: false)),
      ('night motion', NightMotionPainter(_anim, religiousMotifs: false)),
      for (final phase in PrayerSkyPhase.values) ...[
        ('sky ${phase.name}', PrayerSkyStaticPainter(phase, religiousMotifs: false)),
        ('sky motion ${phase.name}', PrayerSkyMotionPainter(_anim, phase)),
      ],
      ('parent', const ParentStaticPainter(religiousMotifs: false)),
      for (final kind in ZadIconKind.values)
        for (final tone in ZadIconTone.values)
          ('icon ${kind.name} ${tone.name}', ZadIconPainter(kind, ZadIconColors.of(kind, tone), religiousMotifs: false)),
      ('celebration', BurstPainter(_anim, seed: 3, count: 20, origin: Alignment.center, still: false)),
    ];

/// Religious motifs built while painting [p] (crescent, dome, eight-point star).
int _religiousMotifsIn(CustomPainter p, {Size size = const Size(360, 640)}) {
  ArtShapes.debugReligiousMotifCount = 0;
  final recorder = ui.PictureRecorder();
  p.paint(Canvas(recorder), size);
  recorder.endRecording().dispose();
  return ArtShapes.debugReligiousMotifCount;
}

Future<void> _pump(WidgetTester tester, Widget child, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: const Size(400, 800), disableAnimations: reduceMotion),
        child: child,
      ),
    ),
  );
}

/// Every piece of text currently rendered.
List<String> _renderedText(WidgetTester tester) => [
      for (final t in tester.widgetList<RichText>(find.byType(RichText))) t.text.toPlainText(),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. no Arabic script in Kids artwork', () {
    test('the Arabic-script check really finds Arabic', () {
      expect(arabicScript.hasMatch('Zad X لأطفال'), isTrue);
      expect(arabicScript.hasMatch('ﷺ'), isTrue); // presentation form
      expect(arabicScript.hasMatch('Zad X Kids · 12:30 PM'), isFalse);
    });

    test('art, brand, splash and schedule widget sources contain no Arabic script', () {
      final files = [for (final p in kidsArtworkSources) ..._dartFiles(p)];
      expect(files.map((f) => f.path), contains(endsWith('brand_logo.dart')));
      expect(files.map((f) => f.path), contains(endsWith('zad_scene_background.dart')));
      final bad = <String>[];
      for (final f in files) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (arabicScript.hasMatch(lines[i])) bad.add('${f.path}:${i + 1}');
        }
      }
      expect(bad, isEmpty, reason: 'Arabic script in Kids artwork sources');
    });

    test('the Kids wordmark is Latin only', () {
      for (final w in KidsWordmark.words) {
        expect(arabicScript.hasMatch(w), isFalse, reason: w);
        expect(RegExp(r'^[A-Z]+$').hasMatch(w), isTrue, reason: w);
      }
    });

    testWidgets('the Kids wordmark renders Latin text only, labelled "Zad X Kids"', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, const Center(child: KidsWordmark()));
      final texts = _renderedText(tester);
      expect(texts, isNotEmpty);
      expect(texts.where(arabicScript.hasMatch), isEmpty);
      expect(find.bySemanticsLabel('Zad X Kids'), findsOneWidget);
      semantics.dispose();
    });

    if (kIsKids) {
      for (final reduce in [false, true]) {
        testWidgets('ZADX_VARIANT=kids: every scene, icon and the logo render without Arabic text '
            '(${reduce ? 'reduce motion' : 'motion'})', (tester) async {
          for (final scene in ZadScene.values) {
            ArtShapes.debugReligiousMotifCount = 0;
            await _pump(
              tester,
              Stack(children: [
                Positioned.fill(child: ZadSceneBackground(scene: scene, progress: 0.6, child: const SizedBox.expand())),
                const Align(alignment: Alignment.topCenter, child: BrandLogo()),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Wrap(children: [
                    for (final kind in ZadIconKind.values)
                      for (final tone in ZadIconTone.values) ZadIcon(kind, tone: tone, size: 32),
                  ]),
                ),
              ]),
              reduceMotion: reduce,
            );
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull, reason: scene.name);
            expect(ArtShapes.debugReligiousMotifCount, 0, reason: '${scene.name}: religious motif painted in Kids');
            expect(_renderedText(tester).where(arabicScript.hasMatch), isEmpty, reason: scene.name);
            expect(find.byType(Image), findsNothing, reason: 'no artwork logo image in Kids');
          }
        });
      }
    }
  });

  group('2. no mosque / dome / crescent / lantern / Islamic star in Kids painters', () {
    test('every Kids painter paints without a religious motif', () {
      for (final (name, painter) in kidsPainters()) {
        expect(_religiousMotifsIn(painter), 0, reason: name);
        expect(_religiousMotifsIn(painter, size: const Size(1024, 768)), 0, reason: '$name (tablet)');
      }
    });

    if (kIsKids) {
      test('ZADX_VARIANT=kids: every painter defaults to the neutral design', () {
        expect(artReligiousMotifs, isFalse);
        expect(const HomeStaticPainter().withMosque, isFalse);
        expect(const NightStaticPainter().religiousMotifs, isFalse);
        expect(NightMotionPainter(_anim).religiousMotifs, isFalse);
        expect(const ParentStaticPainter().religiousMotifs, isFalse);
        expect(const PrayerSkyStaticPainter(PrayerSkyPhase.night).religiousMotifs, isFalse);
        expect(ZadIconPainter(ZadIconKind.prayer, ZadIconColors.of(ZadIconKind.prayer, ZadIconTone.brand)).religiousMotifs, isFalse);
      });

      test('ZADX_VARIANT=kids: drawing a crescent fails loudly', () {
        expect(() => ArtShapes.crescent(const Offset(10, 10), 5), throwsA(isA<AssertionError>()));
        expect(() => ArtShapes.dome(const Offset(0, 10), 10, 0), throwsA(isA<AssertionError>()));
        expect(() => ArtShapes.eightPointStar(const Offset(10, 10), 5), throwsA(isA<AssertionError>()));
      });
    } else {
      test('Zad X Play keeps its mosque, crescent, lanterns and star pattern (detector works)', () {
        expect(artReligiousMotifs, isTrue);
        expect(_religiousMotifsIn(const HomeStaticPainter()), greaterThan(0));
        expect(_religiousMotifsIn(const NightStaticPainter()), greaterThan(0));
        expect(_religiousMotifsIn(const ParentStaticPainter()), greaterThan(0));
        expect(_religiousMotifsIn(const PrayerSkyStaticPainter(PrayerSkyPhase.night)), greaterThan(0));
        expect(
          _religiousMotifsIn(ZadIconPainter(ZadIconKind.prayer, ZadIconColors.of(ZadIconKind.prayer, ZadIconTone.brand))),
          greaterThan(0),
        );
      });
    }
  });

  group('3. English is the Kids default language', () {
    test('first-run language per variant', () {
      for (final device in ['ar', 'en', 'de', 'fr', 'es', 'ur']) {
        expect(defaultLanguageFor(AppVariant.kids, device), 'en', reason: device);
      }
      expect(defaultLanguageFor(AppVariant.islamic, 'en'), 'en');
      expect(defaultLanguageFor(AppVariant.islamic, 'ar'), 'ar');
      expect(defaultLanguageFor(AppVariant.islamic, 'fr'), 'ar');
    });

    test('KidsLocalizations in English is English (no Arabic script)', () {
      final en = kidsLocalizationsFor(const Locale('en'));
      for (final s in [en.greet, en.homeHeroSub, en.tabHome, en.tabGames, en.tabTasks, en.avatarMoon]) {
        expect(arabicScript.hasMatch(s), isFalse, reason: s);
      }
      expect(en.avatarMoon, 'Planet');
    });

    if (kIsKids) {
      test('ZADX_VARIANT=kids: a fresh install starts in English; Arabic stays optional', () async {
        expect(const AppSettings().language, 'en');
        expect(languagePickerOrder.first, 'en');
        expect(supportedLanguages, contains('ar'));
        expect(upcomingLanguages.values.where(arabicScript.hasMatch), isEmpty);

        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final container = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
        addTearDown(container.dispose);
        expect(container.read(settingsProvider).language, 'en');
        expect(container.read(settingsProvider).isRtl, isFalse);
      });
    }
  });

  group('4. no Arabic Letters game in Kids', () {
    test('catalogue, routes and deep links', () {
      expect(zadGamesFor(AppVariant.kids).map((g) => g.id), isNot(contains('letters')));
      expect(zadGamesFor(AppVariant.islamic).map((g) => g.id), contains('letters'));
      final kidsPaths = _paths(appRoutes(variant: AppVariant.kids, rootKey: GlobalKey<NavigatorState>()));
      expect(kidsPaths, isNot(contains(Routes.eduLetters)));
      expect(kidsRedirect(Routes.eduLetters, variant: AppVariant.kids), Routes.home);
      expect(kidsRedirect(Routes.eduLetters, variant: AppVariant.islamic), isNull);
      expect(kidsLocalizationsFor(const Locale('en')).zadGameLetters, isEmpty);
    });

    if (kIsKids) {
      test('ZADX_VARIANT=kids: this build has no learning game and no letters route', () {
        expect(activeZadGames.map((g) => g.id), isNot(contains('letters')));
        expect(_paths(appRoutes(rootKey: GlobalKey<NavigatorState>())), isNot(contains(Routes.eduLetters)));
      });
    } else {
      test('Zad X Play keeps the Arabic Letters game', () {
        expect(activeZadGames.map((g) => g.id), contains('letters'));
        expect(_paths(appRoutes(rootKey: GlobalKey<NavigatorState>())), contains(Routes.eduLetters));
      });
    }
  });
}
