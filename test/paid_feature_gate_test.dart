import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/subscription/paid_feature_gate.dart';
import 'package:zadx/l10n/app_localizations.dart';
import 'package:zadx/services/billing/subscription_service.dart';

Future<void> _pump(WidgetTester tester, Entitlement ent, AppFeature feature, {bool withPin = true}) async {
  // The parent PIN is created in onboarding (FirstRunGate) before child mode is reachable.
  SharedPreferences.setMockInitialValues({if (withPin) 'settings.pin': PinSecurity.hashPin('1234', rounds: 10)});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      entitlementProvider.overrideWith((ref) => Stream.value(ent)),
    ],
    child: MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: PaidFeatureGate(feature: feature, child: const Text('CONTENT')),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('free features are never blocked for a free family', (tester) async {
    for (final f in freeFeatures) {
      await _pump(tester, const Entitlement(), f);
      expect(find.text('CONTENT'), findsOneWidget, reason: f.name);
    }
  });

  testWidgets('paid feature shows the kid-safe card, with no price or buy button', (tester) async {
    await _pump(tester, const Entitlement(), AppFeature.games);
    expect(find.text('CONTENT'), findsNothing);
    expect(find.byKey(const Key('askParentButton')), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
  });

  testWidgets('the upgrade sheet asks for the parent PIN before showing plans', (tester) async {
    await _pump(tester, const Entitlement(), AppFeature.exercises);
    await tester.tap(find.byKey(const Key('askParentButton')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget); // PIN prompt
    expect(find.byKey(const Key('seePlansButton')), findsNothing);
  });

  testWidgets('without a PIN, "Ask a parent" cannot create one: it shows the for-parents setup card', (tester) async {
    await _pump(tester, const Entitlement(), AppFeature.exercises, withPin: false);
    await tester.tap(find.byKey(const Key('askParentButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('parentSetupNeeded')), findsOneWidget);
    expect(find.byType(TextField), findsNothing); // no PIN field a child could fill in
    expect(find.byKey(const Key('seePlansButton')), findsNothing);

    // The button opens the onboarding PIN step (a separate "for parents" screen).
    await tester.tap(find.byKey(const Key('openOnboardingPin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboardingPinScreen')), findsOneWidget);
  });

  testWidgets('a trial (Plus) opens paid features', (tester) async {
    await _pump(tester, const Entitlement(tier: PlanTier.plus, inTrial: true), AppFeature.weeklyReport);
    expect(find.text('CONTENT'), findsOneWidget);
  });
}
