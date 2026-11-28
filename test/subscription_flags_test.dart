// Owner decision 2026-11-28 (zero cost, no Cloud Functions): the plans screen must not advertise
// the AI assistant (it needs a server-held key) or the invite-a-friend rewards (server counting).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/core/feature_flags.dart';
import 'package:zadx/core/server_functions.dart';
import 'package:zadx/features/parent/parent_session.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/subscription/subscription_screen.dart';
import 'package:zadx/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, {FeatureFlags flags = const FeatureFlags(), String lang = 'en'}) async {
  SharedPreferences.setMockInitialValues({
    'settings.pin': PinSecurity.hashPin('1234', rounds: 10),
  });
  final prefs = await SharedPreferences.getInstance();
  // A very tall phone: the lazy ListView builds every card, so absent text is really absent.
  tester.view.physicalSize = const Size(420, 20000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      featureFlagsProvider.overrideWithValue(flags),
      // Never reach Firebase from a test, even with the Blaze flags.
      serverCallsProvider.overrideWithValue(const DisabledServerCalls()),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SubscriptionScreen(),
    ),
  ));
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  container.read(parentUnlockedProvider.notifier).unlock();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _relock(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(MaterialApp))).read(parentUnlockedProvider.notifier).lock();
  await tester.pump();
}

bool _textAnywhere(WidgetTester tester, String text) => find.text(text, skipOffstage: false).evaluate().isNotEmpty;

void main() {
  testWidgets('default (Spark) build: no AI assistant row and no invite rewards card', (tester) async {
    await _pump(tester);
    expect(_textAnywhere(tester, 'AI assistant'), isFalse);
    expect(_textAnywhere(tester, 'Invite friends, earn free months'), isFalse);
    expect(_textAnywhere(tester, "Friend's invite code (optional)"), isFalse);
    // The plan cards themselves are still there.
    expect(_textAnywhere(tester, 'Restore purchases'), isTrue);
    await _relock(tester);
  });

  testWidgets('Arabic: no AI assistant row', (tester) async {
    await _pump(tester, lang: 'ar');
    expect(_textAnywhere(tester, 'مساعد الذكاء الاصطناعي'), isFalse);
    await _relock(tester);
  });

  testWidgets('Blaze build with both flags: the row and the card come back', (tester) async {
    await _pump(
      tester,
      flags: const FeatureFlags(serverFunctionsRequested: true, assistantRequested: true, referralsRequested: true),
    );
    expect(_textAnywhere(tester, 'AI assistant'), isTrue);
    expect(_textAnywhere(tester, 'Invite friends, earn free months'), isTrue);
    await _relock(tester);
  });
}
