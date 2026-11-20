import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/catalog/arabic_letters.dart';
import 'package:zadx/data/catalog/mosque_parts.dart';
import 'package:zadx/data/catalog/prophets_quiz.dart';
import 'package:zadx/features/edu_games/letters/letters_progress.dart';
import 'package:zadx/features/edu_games/letters/letters_quiz.dart';
import 'package:zadx/features/edu_games/mosque/mosque_controller.dart';
import 'package:zadx/features/edu_games/prophets/prophets_quiz_logic.dart';
import 'package:zadx/features/edu_games/quiz_core.dart';
import 'package:zadx/features/edu_games/stars_controller.dart';
import 'package:zadx/features/settings/settings_controller.dart';

Future<SharedPreferences> freshPrefs([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

ProviderContainer containerWith(SharedPreferences prefs) {
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Arabic letters catalog', () {
    test('has the 28 letters, all different', () {
      expect(arabicLetters.length, 28);
      expect(arabicLetters.map((l) => l.char).toSet().length, 28);
      expect(arabicLetters.map((l) => l.nameAr).toSet().length, 28);
      expect(arabicLetters.map((l) => l.nameEn).toSet().length, 28);
    });

    test('non-joining letters only use isolated and final shapes', () {
      final nonJoining = arabicLetters.where((l) => !l.joinsNext).map((l) => l.char).toSet();
      expect(nonJoining, {'ا', 'د', 'ذ', 'ر', 'ز', 'و'});
      for (final l in arabicLetters.where((l) => !l.joinsNext)) {
        expect(l.positions, [LetterPosition.isolated, LetterPosition.finalForm]);
      }
    });
  });

  group('Quran Letters question generation', () {
    for (final level in letterLevels) {
      test('level ${level.number}: distinct choices, answer always present', () {
        for (var seed = 0; seed < 200; seed++) {
          final round = generateLetterRound(level, math.Random(seed));
          expect(round.length, lettersRoundLength);
          for (final q in round) {
            expect(q.choices.length, level.choices);
            expect(q.choices.toSet().length, q.choices.length, reason: 'duplicate choice');
            expect(q.choices.map((l) => l.nameAr).toSet().length, q.choices.length);
            expect(q.choices[q.answerIndex], q.target);
            expect(q.choices.where((c) => c == q.target).length, 1);
            expect(q.choices.every(level.pool.contains), isTrue);
            expect(level.modes, contains(q.mode));
            if (q.mode == LetterMode.formToLetter) {
              expect(q.target.positions, contains(q.position));
            }
          }
        }
      });
    }

    test('targets do not repeat within a round when the pool is big enough', () {
      for (var seed = 0; seed < 50; seed++) {
        final round = generateLetterRound(letterLevels.first, math.Random(seed));
        expect(round.map((q) => q.target).toSet().length, round.length);
      }
    });

    test('look-alike levels use look-alike letters as distractors', () {
      final level = letterLevels.firstWhere((l) => l.lookAlikes);
      final baa = arabicLetters.firstWhere((l) => l.char == 'ب');
      final set = buildChoices(
        correct: baa,
        pool: level.pool,
        count: level.choices,
        rng: math.Random(1),
        preferred: lookAlikesOf(baa),
      );
      expect(set.choices.where((c) => c != baa).every((c) => 'تثني'.contains(c.char)), isTrue);
    });

    test('buildChoices never duplicates even with a tiny pool', () {
      final set = buildChoices(correct: 1, pool: [1, 2, 2], count: 4, rng: math.Random(0));
      expect(set.choices.toSet().length, set.choices.length);
      expect(set.choices, contains(1));
      expect(set.answer, 1);
    });

    test('stars per round are 1–3 and finishing always earns a star', () {
      expect(starsForRound(firstTryCorrect: 8, total: 8), 3);
      expect(starsForRound(firstTryCorrect: 7, total: 8), 3);
      expect(starsForRound(firstTryCorrect: 4, total: 8), 2);
      expect(starsForRound(firstTryCorrect: 0, total: 8), 1);
    });
  });

  group('Heroes of the Prophets', () {
    test('round questions are distinct, choices distinct, answer present', () {
      for (var seed = 0; seed < 200; seed++) {
        final round = generateProphetRound(math.Random(seed));
        expect(round.length, prophetsRoundLength);
        expect(round.map((q) => q.source.id).toSet().length, round.length);
        for (final q in round) {
          expect(q.choices.length, q.source.wrong.length + 1);
          expect(q.choices.map((c) => c.en).toSet().length, q.choices.length);
          expect(q.choices.map((c) => c.ar).toSet().length, q.choices.length);
          expect(q.choices[q.answerIndex], same(q.source.answer));
        }
      }
    });

    test('content is flagged for scholar review and every fact has a valid reference', () {
      expect(reviewedByScholar, isFalse);
      expect(prophetQuestions.map((q) => q.id).toSet().length, prophetQuestions.length);
      for (final q in prophetQuestions) {
        expect(q.refs, isNotEmpty, reason: q.id);
        for (final r in q.refs) {
          final count = surahAyahCounts[r.surah] ?? 0;
          expect(count, greaterThan(0), reason: '${q.id}: unknown surah ${r.surah}');
          expect(r.fromAyah, inInclusiveRange(1, count), reason: q.id);
          if (r.toAyah != null) expect(r.toAyah!, inInclusiveRange(r.fromAyah + 1, count), reason: q.id);
        }
      }
    });

    test('every prophet name carries the honorific', () {
      // Allows tanween / alif after the name (e.g. "نوحًا عليه السلام").
      final arPattern = RegExp('(${prophetNamesAr.join('|')})[ً-ْا]*(?! عليه السلام)(?=[^ً-ْا]|\$)');
      final enPattern = RegExp('\\b(${prophetNamesEn.join('|')})\\b(?!\'s)(?! \\(peace be upon him\\))');
      for (final q in prophetQuestions) {
        final ar = [q.question.ar, q.fact.ar, q.answer.ar, ...q.wrong.map((w) => w.ar)];
        final en = [q.question.en, q.fact.en, q.answer.en, ...q.wrong.map((w) => w.en)];
        for (final s in ar) {
          expect(arPattern.hasMatch(s), isFalse, reason: '${q.id}: missing "عليه السلام" in "$s"');
        }
        for (final s in en) {
          expect(enPattern.hasMatch(s), isFalse, reason: '${q.id}: missing "(peace be upon him)" in "$s"');
        }
        // And each question does name its prophet with the honorific.
        expect(q.question.ar.contains('عليه السلام'), isTrue, reason: q.id);
        expect(q.question.en.contains('(peace be upon him)'), isTrue, reason: q.id);
      }
    });
  });

  group('Star store', () {
    test('earns, spends and never goes negative', () async {
      final c = containerWith(await freshPrefs());
      final stars = c.read(starsProvider.notifier);
      expect(c.read(starsProvider), 0);

      stars.earn(3);
      expect(c.read(starsProvider), 3);
      expect(stars.spend(5), isFalse);
      expect(c.read(starsProvider), 3);
      expect(stars.spend(2), isTrue);
      expect(c.read(starsProvider), 1);
      expect(stars.spend(1), isTrue);
      expect(c.read(starsProvider), 0);
      expect(stars.spend(1), isFalse);
      expect(c.read(starsProvider), 0);

      stars.earn(-4);
      expect(stars.spend(-4), isFalse);
      expect(c.read(starsProvider), 0);
    });

    test('caps a single award and persists the balance', () async {
      final prefs = await freshPrefs();
      final c = containerWith(prefs);
      c.read(starsProvider.notifier).earn(1000);
      expect(c.read(starsProvider), StarsController.maxAwardPerRound);

      final again = containerWith(prefs);
      expect(again.read(starsProvider), StarsController.maxAwardPerRound);
    });

    test('a corrupted negative stored balance loads as zero', () async {
      final c = containerWith(await freshPrefs({StarsController.prefsKey: -7}));
      expect(c.read(starsProvider), 0);
    });
  });

  group('Build Your Mosque', () {
    test('parts are built in order and cost stars', () async {
      final c = containerWith(await freshPrefs());
      final mosque = c.read(mosqueProvider.notifier);

      expect(mosque.nextPart!.id, 'foundation');
      expect(mosque.buildNext(), BuildResult.notEnoughStars);
      expect(c.read(mosqueProvider), 0);

      final total = mosqueParts.fold<int>(0, (sum, p) => sum + p.cost);
      final stars = c.read(starsProvider.notifier);
      var given = 0;
      while (given < total) {
        stars.earn(StarsController.maxAwardPerRound);
        given += StarsController.maxAwardPerRound;
      }
      for (var i = 0; i < mosqueParts.length; i++) {
        expect(mosque.nextPart!.id, mosqueParts[i].id);
        expect(mosque.buildNext(), BuildResult.built);
        expect(c.read(mosqueProvider), i + 1);
      }
      expect(mosque.nextPart, isNull);
      expect(mosque.buildNext(), BuildResult.complete);
      expect(c.read(starsProvider), given - total);
    });

    test('the build order starts with the foundation and ends with the garden', () {
      expect(mosqueParts.map((p) => p.id).toList(), [
        'foundation', 'walls', 'door', 'windows', 'dome', 'minaret', 'crescent', 'carpet', 'lanterns', 'garden', //
      ]);
      expect(mosqueParts.every((p) => p.cost > 0), isTrue);
    });

    test('progress persists and failed builds change nothing', () async {
      final prefs = await freshPrefs();
      final c = containerWith(prefs);
      c.read(starsProvider.notifier).earn(4);
      expect(c.read(mosqueProvider.notifier).buildNext(), BuildResult.built); // foundation (2)
      expect(c.read(starsProvider), 2);
      expect(c.read(mosqueProvider.notifier).buildNext(), BuildResult.notEnoughStars); // walls (3)
      expect(c.read(starsProvider), 2);

      final again = containerWith(prefs);
      expect(again.read(mosqueProvider), 1);
      expect(again.read(starsProvider), 2);
      expect(again.read(mosqueProvider.notifier).nextPart!.id, 'walls');
    });

    test('a stored count out of range is clamped', () async {
      final c = containerWith(await freshPrefs({MosqueController.prefsKey: 99}));
      expect(c.read(mosqueProvider), mosqueParts.length);
    });
  });

  group('Letters progress', () {
    test('levels open one after another and best stars persist', () async {
      final prefs = await freshPrefs();
      final c = containerWith(prefs);
      final p = c.read(lettersProgressProvider.notifier);
      expect(p.isUnlocked(1), isTrue);
      expect(p.isUnlocked(2), isFalse);
      p.record(1, 2);
      p.record(1, 1); // lower score never replaces a better one
      expect(c.read(lettersProgressProvider)[1], 2);
      expect(p.isUnlocked(2), isTrue);

      final again = containerWith(prefs);
      expect(again.read(lettersProgressProvider)[1], 2);
    });
  });
}
