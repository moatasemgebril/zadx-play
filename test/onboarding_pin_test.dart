import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/onboarding/onboarding_pin_screen.dart';
import 'package:zadx/features/parent/parent_gate.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';

/// The parent PIN is created in onboarding, on first launch, before child mode is reachable
/// (Quality Gate item). ParentGate never creates a PIN.
Future<SharedPreferences> _pumpApp(WidgetTester tester, {String? pinHash, Widget? home}) async {
  SharedPreferences.setMockInitialValues({if (pinHash != null) 'settings.pin': pinHash});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Same wiring as app.dart.
      builder: (context, child) => FirstRunGate(child: child!),
      home: home ?? const Scaffold(body: Text('CHILD HOME')),
    ),
  ));
  await tester.pumpAndSettle();
  return prefs;
}

Future<void> _fill(WidgetTester tester, String pin, String again, {bool parent = true}) async {
  await tester.enterText(find.byKey(const Key('onboardingPin')), pin);
  await tester.enterText(find.byKey(const Key('onboardingPinConfirm')), again);
  if (parent) {
    await tester.ensureVisible(find.byKey(const Key('onboardingIsParent')));
    await tester.tap(find.byKey(const Key('onboardingIsParent')));
  }
  await tester.ensureVisible(find.byKey(const Key('onboardingPinSave')));
  await tester.tap(find.byKey(const Key('onboardingPinSave')));
  await tester.pumpAndSettle();
}

void main() {
  group('validateNewPin', () {
    test('4 to 6 digits, typed twice, by a parent', () {
      expect(validateNewPin('1234', '1234', isParent: true), isNull);
      expect(validateNewPin('123456', '123456', isParent: true), isNull);
      expect(validateNewPin('123', '123', isParent: true), NewPinError.tooShort);
      expect(validateNewPin('1234567', '1234567', isParent: true), NewPinError.tooShort);
      expect(validateNewPin('12a4', '12a4', isParent: true), NewPinError.tooShort);
      expect(validateNewPin('1234', '1243', isParent: true), NewPinError.mismatch);
      expect(validateNewPin('1234', '1234', isParent: false), NewPinError.notParent);
    });
  });

  testWidgets('first launch shows only the for-parents PIN step, never child mode', (tester) async {
    await _pumpApp(tester);
    expect(find.byKey(const Key('onboardingPinScreen')), findsOneWidget);
    expect(find.text('CHILD HOME'), findsNothing);
  });

  testWidgets('mismatched PINs or a missing parent confirmation do not save', (tester) async {
    final prefs = await _pumpApp(tester);
    await _fill(tester, '1234', '4321');
    expect(find.byKey(const Key('onboardingPinError')), findsOneWidget);
    expect(prefs.getString('settings.pin'), isNull);

    await tester.ensureVisible(find.byKey(const Key('onboardingIsParent')));
    await tester.tap(find.byKey(const Key('onboardingIsParent'))); // untick again
    await tester.pump();
    await _fill(tester, '1234', '1234', parent: false);
    expect(prefs.getString('settings.pin'), isNull);
    expect(find.text('CHILD HOME'), findsNothing);
  });

  testWidgets('a valid PIN is stored hashed and opens the app', (tester) async {
    final prefs = await _pumpApp(tester);
    await _fill(tester, '2468', '2468');
    final stored = prefs.getString('settings.pin');
    expect(stored, isNotNull);
    expect(stored, isNot(contains('2468')));
    expect(PinSecurity.verifyPin('2468', stored!), isTrue);
    expect(find.text('CHILD HOME'), findsOneWidget);
    expect(find.byKey(const Key('onboardingPinScreen')), findsNothing);
  });

  testWidgets('with a PIN, the app opens straight to child mode', (tester) async {
    await _pumpApp(tester, pinHash: PinSecurity.hashPin('1234', rounds: 10));
    expect(find.text('CHILD HOME'), findsOneWidget);
  });

  testWidgets('ParentGate without a PIN never creates one; it points to the onboarding step', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // No FirstRunGate here: the gate on its own must still be safe.
        home: const Scaffold(body: ParentGate(child: Text('PARENT AREA'))),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('parentSetupNeeded')), findsOneWidget);
    expect(find.text('PARENT AREA'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const Key('openOnboardingPin')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboardingPinScreen')), findsOneWidget);
    await _fill(tester, '1357', '1357');

    // Back on the gate, which now asks for the new PIN (it does not open by itself).
    expect(find.byKey(const Key('onboardingPinScreen')), findsNothing);
    expect(find.text('PARENT AREA'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(PinSecurity.verifyPin('1357', prefs.getString('settings.pin')!), isTrue);
  });
}
