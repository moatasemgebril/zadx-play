// PlayStation lock guide for parents (owner request 2026-11-24): the 7 steps are visible
// in Arabic and English after the parent opens the guide.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/features/parent/ps_lock_steps.dart';
import 'package:zadx/l10n/app_localizations.dart';

Future<AppLocalizations> _pump(WidgetTester tester, String lang) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: PsLockSteps())),
    ),
  );
  await tester.pumpAndSettle();
  return lookupAppLocalizations(Locale(lang));
}

void main() {
  for (final lang in ['en', 'ar']) {
    testWidgets('the PlayStation guide opens and shows all 7 steps ($lang)', (tester) async {
      final l10n = await _pump(tester, lang);
      expect(find.text(l10n.psStepsTitle), findsOneWidget);
      expect(find.text(l10n.psStep1), findsNothing); // collapsed at first

      await tester.tap(find.text(l10n.psStepsTitle));
      await tester.pumpAndSettle();

      for (final step in [
        l10n.psStep1, l10n.psStep2, l10n.psStep3, l10n.psStep4,
        l10n.psStep5, l10n.psStep6, l10n.psStep7,
      ]) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.text('7'), findsOneWidget);
    });
  }
}
