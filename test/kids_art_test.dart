import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/core/theme/app_colors.dart';
import 'package:zadx/shared/art/zad_art.dart';

const _small = Size(360, 640);
const _large = Size(1024, 768);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = _small,
  bool reduceMotion = false,
  TextDirection dir = TextDirection.ltr,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: dir,
      child: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduceMotion),
        child: child,
      ),
    ),
  );
}

void main() {
  group('ZadSceneBackground', () {
    for (final scene in ZadScene.values) {
      for (final size in [_small, _large]) {
        for (final reduce in [false, true]) {
          for (final dir in TextDirection.values) {
            testWidgets('${scene.name} ${size.width.toInt()}x${size.height.toInt()} '
                '${reduce ? 'reduce-motion' : 'motion'} ${dir.name}', (tester) async {
              await _pump(
                tester,
                ZadSceneBackground(scene: scene, progress: 0.5, child: const SizedBox.expand(key: Key('content'))),
                size: size,
                reduceMotion: reduce,
                dir: dir,
              );
              await tester.pump(const Duration(seconds: 3));
              expect(tester.takeException(), isNull);
              expect(find.byKey(const Key('content')), findsOneWidget);

              // Every art layer is isolated in its own repaint boundary.
              final boundaries = find.descendant(of: find.byType(ZadSceneBackground), matching: find.byType(RepaintBoundary));
              expect(boundaries, findsAtLeastNWidgets(1));

              // Motion only when allowed; reduce-motion and the parent area are still.
              final shouldMove = !reduce && scene.loop != null;
              expect(tester.binding.hasScheduledFrame, shouldMove);

              // RTL mirrors the composition.
              final flip = tester.widget<Transform>(
                find.descendant(of: find.byType(ZadSceneBackground), matching: find.byType(Transform)).first,
              );
              expect(flip.transform.storage[0], dir == TextDirection.rtl ? -1.0 : 1.0);
            });
          }
        }
      }
    }

    testWidgets('every prayer sky phase paints at banner and full size', (tester) async {
      for (final phase in PrayerSkyPhase.values) {
        for (final size in [const Size(360, 64), _large]) {
          await _pump(
            tester,
            ZadSceneBackground(scene: ZadScene.prayer, prayerPhase: phase, child: const SizedBox.expand()),
            size: size,
          );
          await tester.pump(const Duration(seconds: 2));
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('garden paints from empty to full and beyond', (tester) async {
      for (final p in [0.0, 0.1, 0.5, 1.0, 1.7, double.nan]) {
        await _pump(tester, ZadSceneBackground(scene: ZadScene.tasks, progress: p, child: const SizedBox.expand()));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('turning reduce-motion on freezes a running scene', (tester) async {
      await _pump(tester, const ZadSceneBackground(scene: ZadScene.home, child: SizedBox.expand()));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await _pump(tester, const ZadSceneBackground(scene: ZadScene.home, child: SizedBox.expand()), reduceMotion: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('animate: false keeps a still frame (quiz screens)', (tester) async {
      await _pump(tester, const ZadSceneBackground(scene: ZadScene.games, animate: false, child: SizedBox.expand()));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('readability', () {
    test('contrast helper matches WCAG reference values', () {
      expect(Contrast.ratio(const Color(0xFFFFFFFF), const Color(0xFF000000)), closeTo(21, 0.01));
      expect(Contrast.ratio(AppColors.muted, const Color(0xFFFFFFFF)), greaterThan(6));
    });

    for (final scene in ZadScene.values.where((s) => s.palette.textOnScene)) {
      test('${scene.name}: body text stays ≥ 4.5:1 on every scene colour under the scrim', () {
        final p = scene.palette;
        expect(p.contentColors, isNotEmpty);
        for (final c in p.contentColors) {
          final bg = Contrast.over(p.scrim, c);
          // Dark scenes (Zad X brand navy) carry light text; light scenes carry ink / muted.
          final texts = p.dark
              ? [AppColors.onNavy, AppColors.onNavyMuted, AppColors.yellow]
              : [AppColors.muted, AppColors.ink, AppColors.purpleDark, AppColors.mintText];
          for (final text in texts) {
            expect(Contrast.ratio(text, bg), greaterThanOrEqualTo(4.5), reason: '$text on $c');
          }
        }
      });
    }
  });

  group('scene logic', () {
    test('garden blooms follow task progress', () {
      expect(gardenBloomCount(0), 0);
      expect(gardenBloomCount(-1), 0);
      expect(gardenBloomCount(double.nan), 0);
      expect(gardenBloomCount(0.01), 1, reason: 'first task always shows a flower');
      expect(gardenBloomCount(0.5), 5);
      expect(gardenBloomCount(1), gardenSlots);
      expect(gardenBloomCount(3), gardenSlots);
    });

    test('prayer sky follows the prayer day', () {
      PrayerSkyPhase at(double now, {double isha = 19.5}) =>
          prayerSkyPhaseFor(now: now, fajr: 5, dhuhr: 12, asr: 15.5, maghrib: 18, isha: isha);
      expect(at(3), PrayerSkyPhase.night);
      expect(at(5.2), PrayerSkyPhase.dawn);
      expect(at(9), PrayerSkyPhase.day);
      expect(at(13), PrayerSkyPhase.day);
      expect(at(16), PrayerSkyPhase.afternoon);
      expect(at(17.8), PrayerSkyPhase.sunset);
      expect(at(19), PrayerSkyPhase.sunset);
      expect(at(20), PrayerSkyPhase.night);
      expect(at(23.9), PrayerSkyPhase.night);
      // Missing Isha (extreme latitudes) falls back to Maghrib + 1.5 h.
      expect(at(19.2, isha: double.nan), PrayerSkyPhase.sunset);
      expect(at(19.6, isha: double.nan), PrayerSkyPhase.night);
    });

    test('crescent and star paths are closed, finite shapes', () {
      for (final path in [
        ArtShapes.crescent(const Offset(50, 50), 20),
        ArtShapes.star(const Offset(50, 50), 20),
        ArtShapes.eightPointStar(const Offset(50, 50), 20),
      ]) {
        final b = path.getBounds();
        expect(b.isFinite, isTrue);
        expect(b.width, greaterThan(10));
        expect(b.right, lessThan(80));
      }
    });
  });

  group('ZadIcon', () {
    for (final dir in TextDirection.values) {
      testWidgets('all icons in all tones build (${dir.name})', (tester) async {
        await _pump(
          tester,
          Wrap(children: [
            for (final kind in ZadIconKind.values)
              for (final tone in ZadIconTone.values)
                for (final size in [24.0, 48.0]) ZadIcon(kind, tone: tone, size: size),
          ]),
          dir: dir,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ZadIcon), findsNWidgets(ZadIconKind.values.length * ZadIconTone.values.length * 2));
      });
    }

    testWidgets('selection bounce is short and skipped with reduce-motion', (tester) async {
      await _pump(tester, const Center(child: ZadIcon(ZadIconKind.home, bounce: true)));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      await _pump(tester, const Center(child: ZadIcon(ZadIconKind.games, key: Key('fresh'), bounce: true)), reduceMotion: true);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('decorative by default, labelled when asked', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const Column(children: [ZadIcon(ZadIconKind.star), ZadIcon(ZadIconKind.help, semanticLabel: 'Help')]));
      expect(find.bySemanticsLabel('Help'), findsOneWidget);
      handle.dispose();
    });
  });

  group('celebration', () {
    for (final reduce in [false, true]) {
      testWidgets('burst ends within 1.5 s (${reduce ? 'reduce-motion' : 'motion'})', (tester) async {
        var done = 0;
        await _pump(
          tester,
          SizedBox.expand(child: ZadCelebrationBurst(onDone: () => done++)),
          reduceMotion: reduce,
        );
        expect(ZadCelebrationBurst.duration, lessThan(const Duration(milliseconds: 1500)));
        await tester.pump(const Duration(milliseconds: 600));
        expect(done, 0);
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump();
        expect(done, 1);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('celebrates only when a value goes up', (tester) async {
      Widget build(List<int> v) => ZadCelebrateOnIncrease(values: v, child: const SizedBox.expand());

      await _pump(tester, build([0, 0]));
      expect(find.byType(ZadCelebrationBurst), findsNothing, reason: 'never on first build');

      await _pump(tester, build([0, 0]));
      expect(find.byType(ZadCelebrationBurst), findsNothing);

      await _pump(tester, build([1, 0]));
      expect(find.byType(ZadCelebrationBurst), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump();
      expect(find.byType(ZadCelebrationBurst), findsNothing);

      await _pump(tester, build([1, 0]));
      expect(find.byType(ZadCelebrationBurst), findsNothing, reason: 'no change, no burst');

      await _pump(tester, build([0, 0]));
      expect(find.byType(ZadCelebrationBurst), findsNothing, reason: 'going down never celebrates');
    });
  });
}
