// Launch splash, one per app (docs/decisions/ZADX-KIDS-VARIANT.md):
// * Zad X Play: logo + "Zad X" + the identity line "لأطفال المسلمين" / "For Muslim Kids";
// * Zad X Kids: the Latin "ZAD X KIDS" wordmark only (no Arabic, no religious line, no artwork logo).
//
// Runs in both builds: `flutter test` and
// `flutter test --dart-define=ZADX_VARIANT=kids test/launch_splash_test.dart` (CI).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/core/app_config.dart';
import 'package:zadx/core/app_variant.dart';
import 'package:zadx/features/splash/launch_splash.dart';

/// Arabic script blocks: Arabic, Supplement, Extended-A, Presentation Forms A and B.
final _arabic = RegExp('[؀-ۿݐ-ݿࢠ-ࣿﭐ-﷿ﹰ-﻿]');

class _FakeApp extends StatelessWidget {
  const _FakeApp();

  @override
  Widget build(BuildContext context) =>
      const Directionality(textDirection: TextDirection.rtl, child: Center(child: Text('APP')));
}

List<String> _renderedText(WidgetTester tester) => [
      for (final t in tester.widgetList<RichText>(find.byType(RichText))) t.text.toPlainText(),
    ];

void _reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  group('brand identity text', () {
    test('Zad X Play says it is for Muslim kids, in Arabic and English, within store limits', () {
      expect(IslamicBrand.identityAr, 'لأطفال المسلمين');
      expect(IslamicBrand.identityEn, 'For Muslim Kids');
      expect(IslamicBrand.identityFor('ar'), IslamicBrand.identityAr);
      expect(IslamicBrand.identityFor('en'), IslamicBrand.identityEn);
      for (final s in [IslamicBrand.storeSubtitleAr, IslamicBrand.storeShortDescriptionAr]) {
        expect(s, contains('المسلمين'), reason: s);
      }
      for (final s in [IslamicBrand.storeSubtitleEn, IslamicBrand.storeShortDescriptionEn]) {
        expect(s, contains('Muslim'), reason: s);
      }
      // App Store subtitle ≤ 30, Google Play short description ≤ 80 (both apps, both languages).
      for (final s in [IslamicBrand.storeSubtitleAr, IslamicBrand.storeSubtitleEn, KidsBrand.storeSubtitleAr, KidsBrand.storeSubtitleEn]) {
        expect(s.runes.length, lessThanOrEqualTo(30), reason: s);
      }
      for (final s in [
        IslamicBrand.storeShortDescriptionAr, IslamicBrand.storeShortDescriptionEn,
        KidsBrand.storeShortDescriptionAr, KidsBrand.storeShortDescriptionEn,
      ]) {
        expect(s.runes.length, lessThanOrEqualTo(80), reason: s);
      }
    });

    test('screen-reader labels per variant', () {
      expect(LaunchSplash.semanticsLabel(AppVariant.kids, 'en'), 'Zad X Kids');
      expect(LaunchSplash.semanticsLabel(AppVariant.kids, 'ar'), 'Zad X Kids');
      if (!kIsKids) {
        expect(LaunchSplash.semanticsLabel(AppVariant.islamic, 'en'), 'Zad X — For Muslim Kids');
        expect(LaunchSplash.semanticsLabel(AppVariant.islamic, 'ar'), 'Zad X — لأطفال المسلمين');
      } else {
        // The Kids build never shows the Zad X Play splash, whatever is asked.
        expect(LaunchSplash.semanticsLabel(AppVariant.islamic, 'ar'), 'Zad X Kids');
      }
    });
  });

  group('Zad X Kids splash', () {
    for (final reduce in [true, false]) {
      testWidgets('Latin "Zad X Kids" only, no Arabic, no artwork logo (${reduce ? 'reduced motion' : 'motion'})',
          (tester) async {
        if (reduce) _reduceMotion(tester);
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(LaunchSplashHost(app: Future.value(const _FakeApp()), variant: AppVariant.kids, language: 'ar'));
        await tester.pump();
        // Mid-reveal (motion) or inside the short hold (reduced motion): the splash is up.
        await tester.pump(Duration(milliseconds: reduce ? 200 : 700));

        expect(find.bySemanticsLabel('Zad X Kids'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Muslim')), findsNothing);
        final texts = _renderedText(tester).where((t) => t != 'APP').toList();
        expect(texts.join(' '), contains('KIDS'));
        expect(texts.where(_arabic.hasMatch), isEmpty, reason: 'no Arabic script on the Kids splash: $texts');
        expect(texts.where((t) => t.contains('Muslim')), isEmpty);
        expect(find.byType(Image), findsNothing, reason: 'the artwork logo (Arabic, crescent, mosques) is never used');
        expect(tester.hasRunningAnimations, reduce ? isFalse : isTrue);

        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Zad X Kids'), findsNothing);
        expect(find.text('APP'), findsOneWidget);
        semantics.dispose();
      });
    }
  });

  if (kIsKids) {
    testWidgets('ZADX_VARIANT=kids: the default splash is the Kids one, even if Play is asked', (tester) async {
      _reduceMotion(tester);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(LaunchSplashHost(app: Future.value(const _FakeApp())));
      await tester.pump();
      expect(find.bySemanticsLabel('Zad X Kids'), findsOneWidget);
      await tester.pumpWidget(LaunchSplashHost(
        key: const ValueKey('again'),
        app: Future.value(const _FakeApp()),
        variant: AppVariant.islamic,
        language: 'ar',
      ));
      await tester.pump();
      expect(find.bySemanticsLabel('Zad X Kids'), findsOneWidget);
      expect(_renderedText(tester).where(_arabic.hasMatch), isEmpty);
      expect(find.byType(Image), findsNothing);
      await tester.pumpAndSettle();
      semantics.dispose();
    });
  }

  if (!kIsKids) {
    group('Zad X Play splash', () {
      testWidgets('reduced motion: no animation, labelled, app shown after a short hold', (tester) async {
        _reduceMotion(tester);
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(LaunchSplashHost(app: Future.value(const _FakeApp()), variant: AppVariant.islamic, language: 'en'));
        await tester.pump(); // the app future resolves

        expect(find.bySemanticsLabel('Zad X — For Muslim Kids'), findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse, reason: 'no reveal animation with reduced motion');
        // The app is already built underneath (start-up is not delayed), but hidden from screen readers.
        expect(find.text('APP'), findsOneWidget);
        expect(find.bySemanticsLabel('APP'), findsNothing);

        await tester.pump(LaunchSplash.reducedMotionHold);
        await tester.pump();

        expect(find.bySemanticsLabel('Zad X — For Muslim Kids'), findsNothing);
        expect(find.text('APP'), findsOneWidget);
        expect(find.bySemanticsLabel('APP'), findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse, reason: 'hand-over without a fade');
        semantics.dispose();
      });

      for (final lang in ['ar', 'en']) {
        testWidgets('the Muslim identity line is shown in Arabic and English ($lang label)', (tester) async {
          _reduceMotion(tester);
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(LaunchSplashHost(app: Completer<Widget>().future, variant: AppVariant.islamic, language: lang));
          await tester.pump();

          final ar = tester.widget<Text>(find.text(IslamicBrand.identityAr));
          expect(ar.textDirection, TextDirection.rtl);
          final en = tester.widget<Text>(find.text(IslamicBrand.identityEn));
          expect(en.textDirection, TextDirection.ltr);
          expect(find.bySemanticsLabel('Zad X — ${IslamicBrand.identityFor(lang)}'), findsOneWidget);
          // Uses BrandLogo (never the jpg directly from the splash) and the Latin wordmark.
          expect(find.byType(Image), findsOneWidget);
          expect(find.text('Zad X'), findsOneWidget);
          expect(find.text('KIDS'), findsNothing, reason: 'no Kids wordmark in Zad X Play');
          semantics.dispose();
        });
      }

      testWidgets('wordmark is Latin "Zad X", left to right, in a ≤1.6 s reveal', (tester) async {
        expect(LaunchSplash.revealDuration + LaunchSplash.exitDuration, lessThanOrEqualTo(const Duration(milliseconds: 1600)));
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(LaunchSplashHost(app: Future.value(const _FakeApp()), variant: AppVariant.islamic, language: 'ar'));
        await tester.pump();
        expect(tester.hasRunningAnimations, isTrue);

        final wordmark = tester.widget<Text>(find.text('Zad X'));
        expect(wordmark.textDirection, TextDirection.ltr);

        await tester.pump(const Duration(milliseconds: 600));
        expect(find.bySemanticsLabel('Zad X — ${IslamicBrand.identityAr}'), findsOneWidget);

        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(RegExp('^Zad X')), findsNothing);
        expect(find.text('APP'), findsOneWidget);
        semantics.dispose();
      });
    });
  }

  testWidgets('splash waits for slow start-up, then hands over (this build)', (tester) async {
    _reduceMotion(tester);
    final app = Completer<Widget>();
    final semantics = tester.ensureSemantics();
    final label = LaunchSplash.semanticsLabel(appVariant, 'en');

    await tester.pumpWidget(LaunchSplashHost(app: app.future, language: 'en'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(find.text('APP'), findsNothing);

    app.complete(const _FakeApp());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(label), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    semantics.dispose();
  });
}
