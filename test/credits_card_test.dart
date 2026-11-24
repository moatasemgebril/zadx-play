// CC BY 3.0 attribution for the bundled adhan (BACKLOG P2, 2026-11-21 PM):
// the parent-area Credits card must show the author, the source link, the
// licence link and the changes made, in Arabic and in English.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/features/parent/credits_card.dart';
import 'package:zadx/l10n/app_localizations.dart';

Future<void> _pump(WidgetTester tester, String lang) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: CreditsCard())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the credit links are the CC BY 3.0 licence and the Wikimedia Commons file', () {
    expect(CreditsCard.adhanLicenceUrl, 'https://creativecommons.org/licenses/by/3.0/');
    expect(
      CreditsCard.adhanSourceUrl,
      'https://commons.wikimedia.org/wiki/File:33937_ejaz215_call-to-prayer-from-the-prophet-s-mo.ogg',
    );
  });

  for (final lang in ['en', 'ar']) {
    testWidgets('the adhan credit shows author, source, licence and changes ($lang)', (tester) async {
      await _pump(tester, lang);
      expect(find.textContaining('ejaz215 · CC BY 3.0'), findsOneWidget);
      expect(find.textContaining('https://creativecommons.org/licenses/by/3.0/'), findsOneWidget);
      expect(find.textContaining(CreditsCard.adhanSourceUrl), findsOneWidget);
      expect(find.textContaining('MP3'), findsOneWidget);
      expect(find.byType(SelectableText), findsWidgets);
    });
  }
}
