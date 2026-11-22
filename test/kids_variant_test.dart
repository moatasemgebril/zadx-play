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
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/data/catalog/games.dart';
import 'package:zadx/data/catalog/praise.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/schedule/scheduled_lock.dart';
import 'package:zadx/router.dart';
import 'package:zadx/variant/kids_localizations.dart';
import 'package:zadx/variant/kids_strings.dart';

/// The single forbidden-word list (also used by the backend test for the assistant prompt).
final Map<String, List<String>> _words = () {
  final raw = jsonDecode(File('tools/kids_forbidden_words.json').readAsStringSync()) as Map<String, dynamic>;
  return {
    'en': [for (final w in raw['en'] as List) (w as String).toLowerCase()],
    'ar': [for (final w in raw['ar'] as List) w as String],
  };
}();

/// Religious words found in [text] (English: whole words, any case; Arabic: anywhere).
List<String> religiousWordsIn(String text) => [
      for (final w in _words['en']!)
        if (RegExp("(?<![A-Za-z'])${RegExp.escape(w)}(?![A-Za-z'])", caseSensitive: false).hasMatch(text)) w,
      for (final w in _words['ar']!)
        if (text.contains(w)) w,
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
    expect(religiousWordsIn('يلا نبدأ يومنا بالصلاة'), contains('الصلا'));
    expect(religiousWordsIn('حروف القرآن'), contains('قرآن'));
    // Everyday words stay allowed.
    expect(religiousWordsIn('Bedtime — tap Display, a fast prayerless task'), isEmpty);
    expect(religiousWordsIn('تنبيه: خلّص جزء من الواجب'), isEmpty);
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
      for (final k in {...kidsRewrites['en']!.keys, ...islamicOnlyL10nKeys}) {
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
      ];
      for (final t in texts) {
        _expectNeutral('KidsText', t.ar);
        _expectNeutral('KidsText', t.en);
      }
    });
  });

  group('Kids brand, store and catalog', () {
    test('separate app id, store name and products; neutral store text', () {
      expect(KidsBrand.storeName, 'Zad X Kids');
      expect(KidsBrand.androidPackage, 'com.zadx.kids');
      expect(KidsBrand.iosBundleId, 'com.zadx.kids');
      for (final t in [KidsBrand.storeName, KidsBrand.storeSubtitleAr, KidsBrand.storeSubtitleEn]) {
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
        expect(p.masculine, isNot(p.feminine), reason: 'Arabic praise must follow the child\'s form of address');
      }
    });

    test('starter tasks: no prayer, Quran or adhkar tasks; homework stays must-do', () {
      final tasks = starterTasksFor(AppVariant.kids);
      expect(tasks.where((t) => islamicTaskKinds.contains(t.kind)), isEmpty);
      expect(tasks.any((t) => t.id == 'homework' && t.required), isTrue);
      for (final t in tasks) {
        _expectNeutral('task ${t.id}', '${t.title.ar} ${t.title.en} ${t.subtitle.ar} ${t.subtitle.en}');
      }
    });

    test('learning games: none in Kids (no prophets, no mosque, no Arabic Letters)', () {
      expect(zadGamesFor(AppVariant.kids), isEmpty);
    });

    test('schedules replace prayer locks', () {
      expect(ScheduleKind.values.map((k) => k.name), containsAll(['bedtime', 'study', 'reading']));
      expect(defaultSchedules.firstWhere((s) => s.kind == ScheduleKind.bedtime).crossesMidnight, isTrue);
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
