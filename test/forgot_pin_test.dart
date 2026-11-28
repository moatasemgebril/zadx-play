import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/parent/parent_gate.dart';
import 'package:zadx/features/parent/pin_recovery.dart';
import 'package:zadx/features/parent/pin_recovery_screen.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';

/// "Forgot PIN?" on the parent gate: offline recovery code (BACKLOG P1 "no PIN recovery").
const _oldCode = 'ABCD-EFGH-JKMN';

Future<SharedPreferences> _pumpGate(
  WidgetTester tester, {
  bool withCode = true,
  Widget child = const Text('PARENT AREA'),
  Locale locale = const Locale('en'),
}) async {
  SharedPreferences.setMockInitialValues({
    'settings.pin': PinSecurity.hashPin('1234', rounds: 10),
    if (withCode) PinRecoveryStore.hashKey: RecoveryCode.hash(_oldCode, rounds: 10),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: ParentGate(child: child)),
    ),
  ));
  await tester.pumpAndSettle();
  return prefs;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.enterText(find.byKey(Key(key)), text);
  await tester.pump();
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await _enter(tester, 'recoveryCodeInput', code);
  await _tapKey(tester, 'recoveryCheckButton');
}

String _shownCode(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('recoveryCodeText'))).data!;

/// Enters [pin] on the gate's own PIN field.
Future<void> _gatePin(WidgetTester tester, String pin) async {
  await tester.enterText(find.byType(TextField), pin);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('right code → new PIN → new code; the old code stops working', (tester) async {
    final prefs = await _pumpGate(tester);
    await _tapKey(tester, 'forgotPinButton');
    expect(find.byKey(const Key('forgotPinScreen')), findsOneWidget);
    // The stored code is never shown again.
    expect(find.byKey(const Key('recoveryCodeText')), findsNothing);
    expect(find.text(_oldCode), findsNothing);

    await _enterCode(tester, 'abcd efgh jkmn'); // lower case and spaces are fine
    expect(find.byKey(const Key('recoveryNewPinStep')), findsOneWidget);

    // New PIN must be valid and typed twice.
    await _enter(tester, 'recoveryNewPin', '2468');
    await _enter(tester, 'recoveryNewPinConfirm', '2469');
    await _tapKey(tester, 'recoveryNewPinSave');
    expect(find.byKey(const Key('recoveryNewPinError')), findsOneWidget);

    await _enter(tester, 'recoveryNewPin', '2468');
    await _enter(tester, 'recoveryNewPinConfirm', '2468');
    await _tapKey(tester, 'recoveryNewPinSave');
    final newCode = _shownCode(tester);
    expect(RecoveryCode.normalize(newCode), isNotNull);
    expect(newCode, isNot(_oldCode));
    expect(find.text('Write this down and keep it away from your child.'), findsOneWidget);
    // Nothing changes until the new code is confirmed.
    expect(PinSecurity.verifyPin('1234', prefs.getString('settings.pin')!), isTrue);
    expect(RecoveryCode.verify(_oldCode, prefs.getString(PinRecoveryStore.hashKey)!), isTrue);

    await _enter(tester, 'recoveryConfirmField', RecoveryCode.lastFour(newCode));
    await _tapKey(tester, 'recoveryConfirmButton');

    expect(find.byKey(const Key('forgotPinScreen')), findsNothing);
    expect(find.text('PIN changed. Enter your new PIN.'), findsOneWidget);
    final pinHash = prefs.getString('settings.pin')!;
    expect(PinSecurity.verifyPin('2468', pinHash), isTrue);
    expect(PinSecurity.verifyPin('1234', pinHash), isFalse);
    final codeHash = prefs.getString(PinRecoveryStore.hashKey)!;
    expect(RecoveryCode.verify(_oldCode, codeHash), isFalse); // old code invalidated
    expect(RecoveryCode.verify(newCode, codeHash), isTrue);
    expect(codeHash, isNot(contains(RecoveryCode.normalize(newCode)!)));

    // Recovery does not open the parent area by itself: the new PIN is needed.
    expect(find.text('PARENT AREA'), findsNothing);
    await _gatePin(tester, '2468');
    expect(find.text('PARENT AREA'), findsOneWidget);
  });

  testWidgets('wrong codes lock out, even before the right code', (tester) async {
    final prefs = await _pumpGate(tester);
    await _tapKey(tester, 'forgotPinButton');

    await _enterCode(tester, 'AAAA-AAAA-AAAA');
    expect(find.text("That code isn't right."), findsOneWidget);
    await _enterCode(tester, 'AAAA-AAAA-AAAB');
    await _enterCode(tester, 'AAAA-AAAA-AAAC');
    expect(find.textContaining('Too many wrong tries'), findsOneWidget);
    expect(prefs.getInt(PinRecoveryStore.failuresKey), 3);

    final check = tester.widget<FilledButton>(find.byKey(const Key('recoveryCheckButton')));
    expect(check.onPressed, isNull);
    final field = tester.widget<TextField>(find.byKey(const Key('recoveryCodeInput')));
    expect(field.enabled, isFalse);
    expect(find.byKey(const Key('recoveryNewPinStep')), findsNothing);
    expect(PinSecurity.verifyPin('1234', prefs.getString('settings.pin')!), isTrue);
  });

  testWidgets('a lock-out from earlier tries still applies when the screen is opened again', (tester) async {
    final prefs = await _pumpGate(tester);
    await prefs.setInt(PinRecoveryStore.failuresKey, 3);
    await prefs.setInt(
      PinRecoveryStore.lockedUntilKey,
      DateTime.now().add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );
    await _tapKey(tester, 'forgotPinButton');
    expect(find.textContaining('Too many wrong tries'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('recoveryCheckButton'))).onPressed, isNull);
  });

  testWidgets('without a code: only an honest explanation, no reset and no input', (tester) async {
    final prefs = await _pumpGate(tester, withCode: false);
    await _tapKey(tester, 'forgotPinButton');
    expect(find.byKey(const Key('forgotNoCode')), findsOneWidget);
    expect(find.textContaining('uninstall and reinstall'), findsOneWidget);
    expect(find.textContaining('This deletes everything saved on this device'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('forgotPinScreen')), matching: find.byType(TextField)),
      findsNothing,
    );
    await _tapKey(tester, 'forgotBack');
    expect(find.byKey(const Key('forgotPinScreen')), findsNothing);
    expect(PinSecurity.verifyPin('1234', prefs.getString('settings.pin')!), isTrue);
    expect(prefs.getString(PinRecoveryStore.hashKey), isNull);
  });

  testWidgets('Arabic: the link reads "نسيت الرمز؟" and the no-code page is in Arabic', (tester) async {
    await _pumpGate(tester, withCode: false, locale: const Locale('ar'));
    expect(find.text('نسيت الرمز؟'), findsOneWidget);
    await _tapKey(tester, 'forgotPinButton');
    expect(find.text('مفيش كود استرجاع على الجهاز ده'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byKey(const Key('forgotNoCode')))), TextDirection.rtl);
  });

  testWidgets('long-presses never reset the PIN or open anything', (tester) async {
    final prefs = await _pumpGate(tester);
    final before = prefs.getString('settings.pin');
    // (A held press on the "Forgot PIN?" button is just a tap: it opens the code screen, which
    // still needs the recovery code. Hidden long-press gestures are what must not exist.)
    await tester.longPress(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.longPress(find.byIcon(Icons.shield_rounded), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('forgotPinScreen')), findsNothing);
    expect(find.text('PARENT AREA'), findsNothing);
    expect(prefs.getString('settings.pin'), before);
    expect(prefs.getString(PinRecoveryStore.hashKey), isNotNull);
  });

  testWidgets('the "Forgot PIN?" link is a 44+ dp target', (tester) async {
    await _pumpGate(tester);
    final size = tester.getSize(find.byKey(const Key('forgotPinButton')));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(size.width, greaterThanOrEqualTo(44));
  });

  group('parent-area card for installs without a code', () {
    Widget area() => ListView(children: const [RecoveryCodeCard()]);

    testWidgets('asks for the PIN again, shows a new code once, stores only its hash', (tester) async {
      final prefs = await _pumpGate(tester, withCode: false, child: area());
      await _gatePin(tester, '1234');
      expect(find.byKey(const Key('recoveryCardMissing')), findsOneWidget);

      // Cancel at the PIN prompt: nothing opens.
      await _tapKey(tester, 'recoveryCardButton');
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoverySetupScreen')), findsNothing);

      await _tapKey(tester, 'recoveryCardButton');
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoverySetupScreen')), findsOneWidget);
      final code = _shownCode(tester);
      expect(prefs.getString(PinRecoveryStore.hashKey), isNull); // not before confirming

      await _enter(tester, 'recoveryConfirmField', RecoveryCode.lastFour(code));
      await _tapKey(tester, 'recoveryConfirmButton');
      expect(find.byKey(const Key('recoverySetupScreen')), findsNothing);
      expect(find.byKey(const Key('recoveryCardSet')), findsOneWidget);
      expect(find.text(code), findsNothing); // never shown again
      final saved = prefs.getString(PinRecoveryStore.hashKey)!;
      expect(RecoveryCode.verify(code, saved), isTrue);
      expect(saved, isNot(contains(RecoveryCode.normalize(code)!)));
    });

    testWidgets('the code page closes, unsaved, when the parent session locks', (tester) async {
      final prefs = await _pumpGate(tester, withCode: false, child: area());
      await _gatePin(tester, '1234');
      await _tapKey(tester, 'recoveryCardButton');
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoverySetupScreen')), findsOneWidget);

      final container = ProviderScope.containerOf(tester.element(find.byKey(const Key('recoverySetupScreen'))));
      container.read(parentUnlockedProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recoverySetupScreen')), findsNothing);
      expect(find.byKey(const Key('recoveryCodeText')), findsNothing);
      expect(prefs.getString(PinRecoveryStore.hashKey), isNull);
    });
  });
}
