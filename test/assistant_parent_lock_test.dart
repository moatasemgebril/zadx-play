import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/help/assistant_parent_lock.dart';
import 'package:zadx/features/help/help_screen.dart';
import 'package:zadx/features/parent/parent_session.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';

/// Child safety (BACKLOG P1, 2026-11-21 PM): the AI assistant in Help needs the parent PIN.
Future<ProviderContainer> _pump(WidgetTester tester, Widget home, {String locale = 'en'}) async {
  SharedPreferences.setMockInitialValues({
    'settings.pin': PinSecurity.hashPin('1234', rounds: 10),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  ));
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
}

const _chat = Text('ASSISTANT CHAT');

void main() {
  testWidgets('without an unlocked parent session the chat is hidden and the child sees "ask a parent"',
      (tester) async {
    await _pump(tester, const Scaffold(body: AssistantParentLock(child: _chat)));
    expect(find.text('ASSISTANT CHAT'), findsNothing);
    expect(find.byKey(const Key('assistantLockedCard')), findsOneWidget);
    expect(find.byKey(const Key('assistantAskParentButton')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('Arabic locked card is shown in Arabic', (tester) async {
    await _pump(tester, const Scaffold(body: AssistantParentLock(child: _chat)), locale: 'ar');
    expect(find.text('المساعد ده للكبار'), findsOneWidget);
    expect(find.text('ASSISTANT CHAT'), findsNothing);
  });

  testWidgets('a wrong PIN keeps the chat hidden', (tester) async {
    await _pump(tester, const Scaffold(body: AssistantParentLock(child: _chat)));
    await tester.tap(find.byKey(const Key('assistantAskParentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '9999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('ASSISTANT CHAT'), findsNothing);
  });

  testWidgets('the parent PIN opens the chat, and re-locking hides it again', (tester) async {
    final container = await _pump(tester, const Scaffold(body: AssistantParentLock(child: _chat)));
    await tester.tap(find.byKey(const Key('assistantAskParentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1234');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('ASSISTANT CHAT'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing); // the PIN sheet closed by itself

    container.read(parentUnlockedProvider.notifier).lock();
    await tester.pumpAndSettle();
    expect(find.text('ASSISTANT CHAT'), findsNothing);
    expect(find.byKey(const Key('assistantLockedCard')), findsOneWidget);
  });

  testWidgets('Help screen: the assistant chat input is not shown to a child', (tester) async {
    await _pump(tester, const HelpScreen());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('assistantLockedCard')), findsOneWidget);
    expect(find.byType(TextField), findsNothing); // no chat input
    expect(find.text('Zad X assistant'), findsNothing);
  });
}
