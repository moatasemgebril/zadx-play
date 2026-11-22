import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/adhkar.dart';

// Verified Islamic decisions (owner, 2026-11-22). Sources are cited in
// lib/data/catalog/adhkar.dart and docs/localization/REVIEW-QUEUE.md.

Dhikr _byId(String id) => adhkar.values.expand((l) => l).firstWhere((d) => d.id == id);

void main() {
  test('verified counts', () {
    expect(_byId('m_bismillah').times, 3);
    expect(_byId('e_bismillah').times, 3);
    expect(_byId('m_hasbi').times, 7);
    expect(_byId('e_hasbi').times, 7);
    expect(_byId('m_subhan').times, 100);
    expect(_byId('e_subhan').times, 100);
    expect(_byId('m_bika').times, 1);
    expect(_byId('e_bika').times, 1);
    expect(_byId('s_ibrahimiya').times, 1);
  });

  test('ids are unique', () {
    final ids = adhkar.values.expand((l) => l).map((d) => d.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('the weak "ten salawat in the morning" item is gone; the reminder has no count or reward', () {
    expect(adhkar.values.expand((l) => l).where((d) => d.id == 's_short'), isEmpty);
    expect(adhkar.values.expand((l) => l).map((d) => d.source), isNot(contains('الطبراني')));
    expect(salawatReminder.ar, 'أكثِروا من الصلاة على النبي ﷺ');
    expect(salawatReminder.ar, isNot(matches(RegExp(r'[0-9٠-٩]'))));
    expect(salawatReminder.en, isNot(matches(RegExp(r'[0-9]'))));
  });

  test('radeetu: Hisn al-Muslim 87 wording, ﷺ kept outside the recited text', () {
    final d = _byId('m_radeetu');
    expect(d.text, isNot(contains('صَلَّى')));
    expect(d.text, isNot(contains('ﷺ')));
    expect(d.text, 'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ نَبِيًّا');
    expect(d.source, 'الترمذي وغيره');
    expect(d.sourceOf('en'), 'At-Tirmidhi and others');
    expect(d.note?.ar, contains('ﷺ'));
  });

  test('kalimat is attributed to At-Tirmidhi (Hisn al-Muslim 97)', () {
    expect(_byId('e_kalimat').source, 'الترمذي');
  });

  test('every source has an English name', () {
    for (final d in adhkar.values.expand((l) => l)) {
      expect(dhikrSourcesEn, contains(d.source), reason: d.id);
    }
  });

  group('wording decisions in the ARB files', () {
    final ar = jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync()) as Map<String, dynamic>;
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;

    test('Asr labels name the schools', () {
      expect(ar['asrStandard'], 'الجمهور (المالكي والشافعي والحنبلي)');
      expect(en['asrStandard'], "Majority (Maliki, Shafi'i, Hanbali)");
      expect(ar['asrHanafi'], 'الحنفي (ظلّ المِثلين)');
      expect(en['asrHanafi'], 'Hanafi (shadow ×2)');
    });

    test('prayerSub: "make wudu if you need to", gender-aware with a masculine fallback', () {
      final v = ar['prayerSub'] as String;
      expect(v, contains('feminine{توضّئي إن لم تكوني على وضوء، ثم صلّي، واضغطي الزر بعدها}'));
      expect(v, contains('masculine{توضّأ إن لم تكن على وضوء، ثم صلِّ، واضغط الزر بعدها}'));
      expect(v, contains('other{توضّأ إن لم تكن على وضوء، ثم صلِّ، واضغط الزر بعدها}'));
      expect(en['prayerSub'], contains('other{Make wudu if you need to, pray, then tap the button}'));
    });

    test('letters count and riwaya label', () {
      expect(ar['lettersLevel3'], contains('حروف الهجاء الثمانية والعشرون'));
      expect(ar['quranRiwaya'], 'رواية حفص عن عاصم');
      expect(en['quranRiwaya'], "Hafs from 'Asim");
    });

    test('ikhlas reminder after prayer has no emoji', () {
      expect(ar['prayerIkhlas'], 'الصلاة لله، والجائزة تشجيعٌ لك');
      expect(en['prayerIkhlas'], 'Prayer is for Allah; the reward is just encouragement.');
      expect(ar['prayerIkhlas'], isNot(contains('🌙')));
    });
  });
}
