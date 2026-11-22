import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/features/splash/launch_splash.dart';

class _FakeApp extends StatelessWidget {
  const _FakeApp();

  @override
  Widget build(BuildContext context) =>
      const Directionality(textDirection: TextDirection.rtl, child: Center(child: Text('APP')));
}

void main() {
  testWidgets('reduced motion: no animation, labelled "Zad X", app shown after a short hold', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(LaunchSplashHost(app: Future.value(const _FakeApp())));
    await tester.pump(); // the app future resolves

    expect(find.bySemanticsLabel('Zad X'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse, reason: 'no reveal animation with reduced motion');
    // The app is already built underneath (start-up is not delayed), but hidden from screen readers.
    expect(find.text('APP'), findsOneWidget);
    expect(find.bySemanticsLabel('APP'), findsNothing);

    await tester.pump(LaunchSplash.reducedMotionHold);
    await tester.pump();

    expect(find.bySemanticsLabel('Zad X'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    expect(find.bySemanticsLabel('APP'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse, reason: 'hand-over without a fade');
    semantics.dispose();
  });

  testWidgets('wordmark is Latin "Zad X", left to right, in a ≤1.6 s reveal', (tester) async {
    expect(LaunchSplash.revealDuration + LaunchSplash.exitDuration, lessThanOrEqualTo(const Duration(milliseconds: 1600)));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(LaunchSplashHost(app: Future.value(const _FakeApp())));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);

    final wordmark = tester.widget<Text>(find.text('Zad X'));
    expect(wordmark.textDirection, TextDirection.ltr);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.bySemanticsLabel('Zad X'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Zad X'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('splash waits for slow start-up, then hands over', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final app = Completer<Widget>();

    await tester.pumpWidget(LaunchSplashHost(app: app.future));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Zad X'), findsOneWidget);
    expect(find.text('APP'), findsNothing);

    app.complete(const _FakeApp());
    await tester.pumpAndSettle();
    expect(find.text('Zad X'), findsNothing);
    expect(find.text('APP'), findsOneWidget);
  });
}
