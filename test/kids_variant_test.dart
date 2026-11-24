// Zad X Kids must contain NOTHING religious (owner decision 2026-11-22,
// docs/decisions/ZADX-KIDS-VARIANT.md).
//
// Runs twice in CI:
//   flutter test                                              (Zad X Play build: checks the Kids config explicitly)
//   flutter test --dart-define=ZADX_VARIANT=kids test/kids_variant_test.dart   (the real Kids build constants)
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zadx/core/app_config.dart';
import 'package:zadx/core/app_variant.dart';
import 'package:zadx/core/localized.dart';
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/data/catalog/games.dart';
import 'package:zadx/data/catalog/praise.dart';
import 'package:zadx/data/catalog/reading_stories.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/reading/reading_tasks.dart';
import 'package:zadx/features/schedule/scheduled_lock.dart';
import 'package:zadx/router.dart';
import 'package:zadx/variant/kids_localizations.dart';
import 'package:zadx/variant/kids_strings.dart';
import 'package:zadx/variant/us_english.dart';

/// The single forbidden-word list (also used by the backend test for the assistant prompt).
final Map<String, List<String>> _words = () {
  final raw = jsonDecode(File('tools/kids_forbidden_words.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    'en': [for (final w in raw['en'] as List) (w as String).toLowerCase()],
    'ar': [for (final w in raw['ar'] as List) w as String],
  };
}();

/// Arabic letters and diacritics (word characters for the Arabic whole-word match).
const _arLetter = r'[\u0621-\u063A\u0640-\u065F\u0670-\u06D3\u06FA-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDF9\uFE70-\uFEFC]';

/// Whole-word pattern for an Arabic entry: optional attached prefixes و/ف, then ب/ل/ك, then the
/// article ال (or لل = ل + ال). An entry that itself starts with ال must keep an article.
RegExp _arabicWord(String w) {
  final hasArticle = w.startsWith('ال') && w.length > 3;
  final base = RegExp.escape(hasArticle ? w.substring(2) : w);
  final prefix = hasArticle ? '[وف]?(?:[بك]?ال|لل)' : '[وف]?(?:[بك]?ال|لل|[بلك])?';
  return RegExp('(?<!$_arLetter)$prefix$base(?!$_arLetter)');
}

final Map<String, RegExp> _arPatterns = {for (final w in _words['ar']!) w: _arabicWord(w)};

/// Religious words found in [text]. English: whole words, any case. Arabic: whole words with the
/// attached prefixes و ف ب ل ك ال (so "بسمة" / "المكسورة" are not "بسم" / "سورة").
List<String> religiousWordsIn(String text) => [
      for (final w in _words['en']!)
        if (RegExp("(?<![A-Za-z'])${RegExp.escape(w)}(?![A-Za-z'])", caseSensitive: false).hasMatch(text)) w,
      for (final e in _arPatterns.entries)
        if (e.value.hasMatch(text)) e.key,
    ];

Map<String, String> _arb(String lang) {
  final raw = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
  return {
    for (final e in raw.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
}

/// What the Kids build shows for each ARB key (see kids_strings.dart).
Map<String, String> _kidsStrings(String lang) => {
      for (final e in _arb(lang).entries) e.key: kidsText(lang, e.key) ?? e.value,
    };

Set<String> _placeholders(String s) => RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m[1]!).toSet();

List<String> _paths(List<RouteBase> routes) => [
      for (final r in routes) ...[
        if (r is GoRoute) r.path,
        ..._paths(r.routes),
      ],
    ];

void _expectNeutral(String label, String text) {
  expect(religiousWordsIn(text), isEmpty, reason: '$label: "$text"');
}

void main() {
  test('the forbidden-word check really finds religious words', () {
    expect(religiousWordsIn('Hear the Adhan'), contains('adhan'));
    expect(religiousWordsIn('MashaAllah, well done!'), containsAll(['mashaallah']));
    expect(religiousWordsIn('يلا نبدأ يومنا بالصلاة'), contains('صلاة'));
    expect(religiousWordsIn('حروف القرآن'), contains('قرآن'));
    expect(religiousWordsIn('وبالقرآن نتعلم'), contains('قرآن'));
    expect(religiousWordsIn('رايح للمسجد'), contains('مسجد'));
    expect(religiousWordsIn('والله برافو'), contains('الله'));
    expect(religiousWordsIn('بسم الله'), containsAll(['بسم', 'الله']));
    expect(religiousWordsIn('صلاتك أهم'), contains('صلاتك'));
    // Everyday words stay allowed.
    expect(religiousWordsIn('Bedtime — tap Display, a fast prayerless task'), isEmpty);
    expect(religiousWordsIn('تنبيه: خلّص جزء من الواجب'), isEmpty);
    // Whole words only: no false hits inside longer words.
    expect(religiousWordsIn('بسمة حلوة'), isEmpty); // "smile", not "بسم"
    expect(religiousWordsIn('اللعبة المكسورة'), isEmpty); // "the broken toy", not "سورة"
    expect(religiousWordsIn('صورة الشمس'), isEmpty);
    expect(religiousWordsIn('أنا سعيد'), isEmpty);
  });

  test('US English check finds British words and fixes them', () {
    expect(britishWordsIn('Ask your mum or dad'), isNotEmpty);
    expect(kidsUsEnglish('Ask your mum or dad to open it for you'), 'Ask a parent or grown-up to open it for you');
    expect(kidsUsEnglish('Mum loves this colour'), 'Mom loves this color');
    expect(kidsUsEnglish('At break time, before the end of term'), 'At recess, before the end of the school year');
    expect(kidsUsEnglish('My favourite book'), 'My favorite book');
    expect(kidsUsEnglish('A long-term plan with terms'), 'A long-term plan with terms');
    expect(kidsUsEnglish('Museum'), 'Museum'); // "mum" only as a whole word
    expect(britishWordsIn('Ask a parent or grown-up'), isEmpty);
    expect(const Localized('', 'Tidy your room').enKids, 'Clean your room');
  });

  group('Kids strings (ARB + kids_strings.dart)', () {
    for (final lang in const ['ar', 'en']) {
      test('no religious word in any $lang string the Kids build can show', () {
        final strings = _kidsStrings(lang);
        final bad = {
          for (final e in strings.entries)
            if (religiousWordsIn(e.value).isNotEmpty) e.key: religiousWordsIn(e.value),
        };
        expect(bad, isEmpty, reason: 'Add these keys to kidsRewrites or islamicOnlyL10nKeys in lib/variant/kids_strings.dart');
      });
    }

    test('Kids English is US English (no British word in any Kids-visible English string)', () {
      final strings = _kidsStrings('en');
      final bad = {
        for (final e in strings.entries)
          if (britishWordsIn(e.value).isNotEmpty) e.key: britishWordsIn(e.value),
      };
      expect(bad, isEmpty, reason: 'Add a US English rewrite to kidsRewrites[\'en\'] (lib/variant/kids_strings.dart)');
    });

    test('settings Kids does not offer are empty: Arabic form of address, Zad X Guard for Windows', () {
      final en = kidsLocalizationsFor(const Locale('en'));
      expect(en.formOfAddress, isEmpty);
      expect(en.addressBoy, isEmpty);
      expect(en.addressGirl, isEmpty);
      expect(en.downloadWindows, isEmpty);
      for (final lang in const ['ar', 'en']) {
        final s = _kidsStrings(lang);
        for (final key in const ['pairNote', 'psScheduleNote', 'msScheduleNote', 'faq6A']) {
          expect(s[key]!.toLowerCase(), isNot(contains('guard')), reason: '$lang $key');
          expect(s[key], isNot(contains('PC')), reason: '$lang $key');
        }
        // The console notes no longer refer to the prayer play windows ("enter these times").
        expect(s['psScheduleNote'], isNot(equals(_arb(lang)['psScheduleNote'])));
        expect(s['msScheduleNote'], isNot(equals(_arb(lang)['msScheduleNote'])));
      }
      final arbKeys = _arb('en').keys.toSet();
      for (final k in kidsHiddenL10nKeys) {
        expect(arbKeys, contains(k));
      }
    });

    test('rewrites exist in both languages, match ARB keys and keep the placeholders', () {
      expect(kidsRewrites['en']!.keys.toSet(), kidsRewrites['ar']!.keys.toSet());
      for (final lang in const ['ar', 'en']) {
        final arb = _arb(lang);
        for (final e in kidsRewrites[lang]!.entries) {
          expect(arb.containsKey(e.key), isTrue, reason: 'unknown ARB key ${e.key}');
          expect(_placeholders(e.value), _placeholders(arb[e.key]!), reason: '$lang ${e.key}');
          expect(e.value.trim(), isNotEmpty, reason: '$lang ${e.key}');
        }
      }
      final arbKeys = _arb('ar').keys.toSet();
      for (final k in islamicOnlyL10nKeys) {
        expect(arbKeys, contains(k), reason: 'unknown ARB key $k');
        expect(kidsRewrites['en']!.containsKey(k), isFalse, reason: '$k is both rewritten and Islamic-only');
      }
    });

    test('KidsLocalizations overrides every rewritten and Islamic-only key', () {
      final src = File('lib/variant/kids_localizations.dart').readAsStringSync();
      for (final k in {...kidsRewrites['en']!.keys, ...islamicOnlyL10nKeys, ...kidsHiddenL10nKeys}) {
        expect(RegExp('(get $k =>|String $k\\()').hasMatch(src), isTrue, reason: 'missing override for $k');
      }
    });

    test('KidsLocalizations returns the Kids text', () {
      final en = kidsLocalizationsFor(const Locale('en'));
      final ar = kidsLocalizationsFor(const Locale('ar'));
      expect(en.greet, kidsRewrites['en']!['greet']);
      expect(ar.greet, kidsRewrites['ar']!['greet']);
      expect(en.tabQuran, isEmpty);
      expect(ar.hearAdhan, isEmpty);
      expect(en.nextPrayer('x', 'y'), isEmpty);
      expect(ar.faq2Q, kidsRewrites['ar']!['faq2Q']);
      // Untouched shared strings still come from the ARB files.
      expect(en.tabHome, _arb('en')['tabHome']);
    });

    test('Kids-only UI text (schedules, wordmark) is neutral', () {
      final texts = [
        KidsText.wordmarkKids, KidsText.schedulesTitle, KidsText.schedulesNote, KidsText.study, KidsText.studyNote,
        KidsText.bedtime, KidsText.bedtimeNote, KidsText.reading, KidsText.readingNote, KidsText.from, KidsText.to,
        KidsText.days, KidsText.todayTitle, KidsText.off, KidsText.lockedNow, KidsText.childScheduleLocked,
        KidsText.lockStudy, KidsText.lockBedtime, KidsText.lockReading, ...KidsText.weekdays,
        KidsText.zoneNote('America/New_York'),
      ];
      for (final t in texts) {
        _expectNeutral('KidsText', t.ar);
        _expectNeutral('KidsText', t.en);
        expect(britishWordsIn(t.en), isEmpty, reason: t.en);
      }
    });
  });

  group('Kids brand, store and catalog', () {
    test('separate app id, store name and products; neutral store text', () {
      expect(KidsBrand.storeName, 'Zad X Kids');
      expect(KidsBrand.androidPackage, 'com.zadx.kids');
      expect(KidsBrand.iosBundleId, 'com.zadx.kids');
      for (final t in [
        KidsBrand.storeName, KidsBrand.storeSubtitleAr, KidsBrand.storeSubtitleEn,
        KidsBrand.storeShortDescriptionAr, KidsBrand.storeShortDescriptionEn,
      ]) {
        _expectNeutral('KidsBrand', t);
      }
      final kidsProducts = {
        KidsBrand.productBasicMonthly, KidsBrand.productBasicYearly, KidsBrand.productPlusMonthly, KidsBrand.productPlusYearly,
      };
      expect(kidsProducts, hasLength(4));
      for (final p in kidsProducts) {
        expect(p, startsWith('zadx_kids_'));
      }
      expect(kidsProducts.intersection({
        IslamicBrand.productBasicMonthly, IslamicBrand.productBasicYearly, IslamicBrand.productPlusMonthly, IslamicBrand.productPlusYearly,
      }), isEmpty);
    });

    test('backend PRODUCTS accepts the Kids product ids (same tiers)', () {
      final ts = File('backend/functions/src/security.ts').readAsStringSync();
      for (final (id, tier) in [
        (KidsBrand.productBasicMonthly, 'basic'), (KidsBrand.productBasicYearly, 'basic'),
        (KidsBrand.productPlusMonthly, 'plus'), (KidsBrand.productPlusYearly, 'plus'),
      ]) {
        expect(ts, contains('$id: { tier: "$tier", app: "kids" }'));
      }
    });

    test('praise phrases are neutral, gender-aware and never repeat the Islamic list', () {
      expect(kidsPraisePhrases, hasLength(greaterThanOrEqualTo(5)));
      for (final p in kidsPraisePhrases) {
        _expectNeutral('praise', p.masculine);
        _expectNeutral('praise', p.feminine);
        _expectNeutral('praise', p.en);
        expect(britishWordsIn(p.en), isEmpty, reason: p.en);
        expect(p.masculine, isNot(p.feminine), reason: 'Arabic praise must follow the child\'s form of address');
      }
    });

    test('starter tasks: no prayer, Quran or adhkar tasks; homework stays must-do', () {
      final tasks = starterTasksFor(AppVariant.kids);
      expect(tasks.where((t) => islamicTaskKinds.contains(t.kind)), isEmpty);
      expect(tasks.any((t) => t.id == 'homework' && t.required), isTrue);
      for (final t in tasks) {
        _expectNeutral('task ${t.id}', '${t.title.ar} ${t.title.en} ${t.subtitle.ar} ${t.subtitle.en}');
        // What Kids shows in English is US English.
        expect(britishWordsIn('${t.title.enKids} ${t.subtitle.enKids}'), isEmpty, reason: t.id);
      }
    });

    test('rewards and game tags (games the parent can lock) are neutral', () {
      for (final g in controlledGames) {
        _expectNeutral('game ${g.id}', '${g.name} ${g.tag.ar} ${g.tag.en}');
        expect(britishWordsIn(g.tag.enKids), isEmpty, reason: g.id);
      }
      for (final t in starterTasksFor(AppVariant.kids)) {
        expect(t.rewardMinutes, greaterThan(0), reason: 'every Kids task rewards screen time');
      }
    });

    test('notifications a Kids family can get are neutral (backend texts)', () {
      final ts = File('backend/functions/src/security.ts').readAsStringSync();
      final body = RegExp(r'export function parentNotificationBody[\s\S]*?\n}').firstMatch(ts)![0]!;
      // Everything after the adhan branch (which returns null for Kids) is what Kids can receive.
      final kidsPart = body.substring(body.indexOf('type === "task_submitted"'));
      _expectNeutral('task notification', kidsPart);
      expect(body, contains('if (familyVariant === "kids") return null;'));
      final alert = RegExp(r'export function protectionAlertText[\s\S]*?\n}').firstMatch(ts)![0]!;
      _expectNeutral('protection alert', alert);
    });

    test('learning games: none in Kids (no prophets, no mosque, no Arabic Letters)', () {
      expect(zadGamesFor(AppVariant.kids), isEmpty);
    });

    test('reading homework (shared with Zad X Play) is neutral; its English text has no Arabic script', () {
      final arabic = RegExp('[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]');
      final texts = <Localized>[
        for (final s in readingStories) ...[
          s.title,
          ...s.paragraphs,
          for (final q in s.questions) ...[q.prompt, ...q.options],
        ],
        for (final t in [ReadingTasks.story(ReadingLevel.age5to7), ReadingTasks.book(15)]) ...[t.title, t.subtitle],
      ];
      expect(texts, isNotEmpty);
      for (final t in texts) {
        _expectNeutral('reading', t.ar);
        _expectNeutral('reading', t.en);
        expect(arabic.hasMatch(t.en), isFalse, reason: t.en);
        // Zad X Kids shows the stories in US English (Localized.of -> kidsUsEnglish).
        expect(britishWordsIn(t.enKids), isEmpty, reason: t.enKids);
      }
    });

    test('reading stories: US English in Kids, British English kept for Zad X Play', () {
      final classmate = storyById('new_classmate')!;
      final play = classmate.paragraphs.map((p) => p.en).join(' ');
      final kids = classmate.paragraphs.map((p) => p.enKids).join(' ');
      expect(play, contains('break time'));
      expect(kids, isNot(contains('break time')));
      expect(kids, contains('recess'));
      expect(kids, contains('first day of school'));
      expect(storyById('broken_vase')!.paragraphs.map((p) => p.enKids).join(' '), contains('Mom'));
      // What the Kids build really renders.
      expect(classmate.paragraphs.first.of('en'), kIsKids ? classmate.paragraphs.first.enKids : classmate.paragraphs.first.en);
    });

    test('schedules replace prayer locks', () {
      expect(ScheduleKind.values.map((k) => k.name), containsAll(['bedtime', 'study', 'reading']));
      expect(defaultSchedules.firstWhere((s) => s.kind == ScheduleKind.bedtime).crossesMidnight, isTrue);
    });

    test('Western school week: Kids studies Monday–Friday, Play keeps Sunday–Thursday', () {
      ScheduledLock study(AppVariant v) => defaultSchedulesFor(v).firstWhere((s) => s.kind == ScheduleKind.study);
      expect(study(AppVariant.kids).weekdays, {DateTime.monday, DateTime.tuesday, DateTime.wednesday, DateTime.thursday, DateTime.friday});
      expect(study(AppVariant.islamic).weekdays, schoolDays);
      expect(schoolDays, contains(DateTime.sunday));
      expect(defaultSchedules, defaultSchedulesFor(appVariant));
    });

    test('the week starts on the phone locale (Sunday in the US)', () {
      expect(firstWeekdayFor('en', 'US'), DateTime.sunday);
      expect(firstWeekdayFor('en', 'GB'), DateTime.monday);
      expect(firstWeekdayFor('de', 'DE'), DateTime.monday);
      expect(firstWeekdayFor('ar', 'EG'), DateTime.saturday);
      expect(firstWeekdayFor('en'), DateTime.sunday);
      expect(weekdayOrder(DateTime.sunday), [7, 1, 2, 3, 4, 5, 6]);
      expect(weekdayOrder(DateTime.monday), [1, 2, 3, 4, 5, 6, 7]);
      expect(weekdayOrder(DateTime.saturday), [6, 7, 1, 2, 3, 4, 5]);
    });
  });

  group('Kids routes and plans', () {
    test('no route reaches Quran, prayer, adhan, adhkar, prophets or the mosque game', () {
      final paths = _paths(appRoutes(variant: AppVariant.kids, rootKey: GlobalKey<NavigatorState>()));
      expect(paths, containsAll([Routes.home, Routes.games, Routes.tasks, Routes.parent]));
      for (final p in paths) {
        expect(Routes.playOnly, isNot(contains(p)));
        expect(RegExp('quran|prayer|adhan|adhkar|prophet|masjid|mosque', caseSensitive: false).hasMatch(p), isFalse, reason: p);
      }
      expect(shellTabsFor(variant: AppVariant.kids), isNot(contains(ShellTab.quran)));
      expect(shellTabsFor(variant: AppVariant.kids).map((t) => t.path).toList(),
          [Routes.home, Routes.games, Routes.tasks, Routes.parent]);
    });

    test('an old Islamic deep link opens Home in Kids', () {
      expect(kidsRedirect('/quran', variant: AppVariant.kids), Routes.home);
      expect(kidsRedirect('/edu/masjid', variant: AppVariant.kids), Routes.home);
      expect(kidsRedirect('/games', variant: AppVariant.kids), isNull);
      expect(kidsRedirect('/quran', variant: AppVariant.islamic), isNull);
    });

    test('no plan contains Quran, prayer times, adhan or adhkar; tiers are unchanged', () {
      for (final tier in [null, ...PlanTier.values]) {
        final f = featuresOf(tier, variant: AppVariant.kids);
        expect(f.intersection(islamicOnlyFeatures), isEmpty, reason: '$tier');
        expect(f, featuresOf(tier, variant: AppVariant.islamic).difference(islamicOnlyFeatures));
      }
      expect(featuresOf(null, variant: AppVariant.kids), {AppFeature.appLock});
      const trial = Entitlement(tier: PlanTier.plus, inTrial: true);
      for (final f in islamicOnlyFeatures) {
        expect(hasFeature(trial, f, variant: AppVariant.kids), isFalse, reason: f.name);
      }
      expect(hasFeature(trial, AppFeature.tasksRewards, variant: AppVariant.kids), isTrue);
    });
  });

  group('this build', () {
    if (kIsKids) {
      test('ZADX_VARIANT=kids: every default is the Kids one', () {
        expect(appVariant, AppVariant.kids);
        expect(AppConfig.storeName, 'Zad X Kids');
        expect(AppConfig.androidPackage, 'com.zadx.kids');
        expect(AppConfig.allProductIds.every((p) => p.startsWith('zadx_kids_')), isTrue);
        expect(featuresOf(null), {AppFeature.appLock});
        expect(hasFeature(const Entitlement(), AppFeature.quran), isFalse);
        expect(shellTabsFor(), isNot(contains(ShellTab.quran)));
        expect(_paths(appRoutes(rootKey: GlobalKey<NavigatorState>())).toSet().intersection(Routes.playOnly), isEmpty);
        expect(activePraisePhrases, same(kidsPraisePhrases));
        expect(activeZadGames, isEmpty);
        expect(starterTasks.where((t) => islamicTaskKinds.contains(t.kind)), isEmpty);
      });
    } else {
      test('default build is still Zad X Play', () {
        expect(appVariant, AppVariant.islamic);
        expect(AppConfig.storeName, 'Zad X Play');
        expect(AppConfig.androidPackage, 'com.zadx.app');
        expect(featuresOf(null), contains(AppFeature.quran));
        expect(shellTabsFor(), contains(ShellTab.quran));
        expect(_paths(appRoutes(rootKey: GlobalKey<NavigatorState>())), containsAll(Routes.playOnly));
        expect(activePraisePhrases, same(praisePhrases));
      });
    }
  });
}
