import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/parent/parent_gate.dart';
import 'package:zadx/features/parent/parent_session.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';

/// Parent PIN session re-locks after 2 minutes idle and when the app leaves the screen
/// (owner decision 2026-11-21).
void main() {
  Future<void> pumpGate(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.pin': PinSecurity.hashPin('1234', rounds: 10),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: ParentGate(child: SizedBox.expand(child: Center(child: Text('PARENT AREA')))),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('PARENT AREA'), findsOneWidget);
  }

  testWidgets('correct PIN opens the parent area', (tester) async {
    await pumpGate(tester);
    expect(find.text('PARENT AREA'), findsNothing);
    await enterPin(tester);
  });

  testWidgets('re-locks after 2 minutes without a touch', (tester) async {
    await pumpGate(tester);
    await enterPin(tester);
    await tester.pump(const Duration(minutes: 1, seconds: 59));
    expect(find.text('PARENT AREA'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('PARENT AREA'), findsNothing);
    expect(find.byType(TextField), findsOneWidget); // PIN prompt again
  });

  testWidgets('a touch restarts the 2-minute idle timer', (tester) async {
    await pumpGate(tester);
    await enterPin(tester);
    await tester.pump(const Duration(minutes: 1, seconds: 30));
    await tester.tap(find.text('PARENT AREA'));
    await tester.pump(const Duration(minutes: 1, seconds: 30));
    expect(find.text('PARENT AREA'), findsOneWidget);
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('PARENT AREA'), findsNothing);
  });

  for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
    testWidgets('re-locks immediately when the app goes to the background ($state)', (tester) async {
      await pumpGate(tester);
      await enterPin(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      if (state == AppLifecycleState.paused) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      }
      await tester.pumpAndSettle();
      expect(find.text('PARENT AREA'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('PARENT AREA'), findsNothing); // PIN needed again
    });
  }

  testWidgets('inactive alone (purchase sheet, permission dialog) keeps the session', (tester) async {
    await pumpGate(tester);
    await enterPin(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.text('PARENT AREA'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('PARENT AREA'), findsOneWidget);
  });

  test('session rules without widgets', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final s = c.read(parentUnlockedProvider.notifier);
    expect(c.read(parentUnlockedProvider), isFalse);
    s.touch(); // a touch never unlocks
    expect(c.read(parentUnlockedProvider), isFalse);
    s.unlock();
    expect(c.read(parentUnlockedProvider), isTrue);
    s.onLifecycle(AppLifecycleState.inactive);
    expect(c.read(parentUnlockedProvider), isTrue);
    s.onLifecycle(AppLifecycleState.detached);
    expect(c.read(parentUnlockedProvider), isFalse);
    expect(ParentSession.idleTimeout, const Duration(minutes: 2));
  });
}
