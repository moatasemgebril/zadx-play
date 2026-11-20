import 'dart:math' as math;

import '../../../data/catalog/arabic_letters.dart';
import '../quiz_core.dart';

enum LetterMode {
  /// See a letter, pick its name.
  letterToName,

  /// See a name, pick the letter.
  nameToLetter,

  /// See a letter in one of its positional shapes, pick the letter (older kids).
  formToLetter,
}

/// One difficulty level of the Quran Letters game.
class LetterLevel {
  const LetterLevel({
    required this.number,
    required this.modes,
    required this.poolSize,
    required this.choices,
    this.lookAlikes = false,
  });

  final int number;
  final List<LetterMode> modes;

  /// How many letters (from the start of the alphabet) this level uses.
  final int poolSize;

  /// Number of answer buttons (3 or 4).
  final int choices;

  /// Prefer letters that look alike as wrong answers.
  final bool lookAlikes;

  List<ArabicLetter> get pool => arabicLetters.take(poolSize).toList();

  bool get isFormsLevel => modes.contains(LetterMode.formToLetter);
}

const letterLevels = <LetterLevel>[
  LetterLevel(number: 1, modes: [LetterMode.letterToName], poolSize: 10, choices: 3),
  LetterLevel(number: 2, modes: [LetterMode.nameToLetter], poolSize: 18, choices: 3),
  LetterLevel(number: 3, modes: [LetterMode.letterToName, LetterMode.nameToLetter], poolSize: 28, choices: 4),
  LetterLevel(
    number: 4,
    modes: [LetterMode.letterToName, LetterMode.nameToLetter],
    poolSize: 28,
    choices: 4,
    lookAlikes: true,
  ),
  LetterLevel(number: 5, modes: [LetterMode.formToLetter], poolSize: 28, choices: 4, lookAlikes: true),
];

const lettersRoundLength = 8;

class LetterQuestion {
  const LetterQuestion({
    required this.mode,
    required this.target,
    required this.choiceSet,
    this.position = LetterPosition.isolated,
  });

  final LetterMode mode;
  final ArabicLetter target;
  final ChoiceSet<ArabicLetter> choiceSet;

  /// Only meaningful for [LetterMode.formToLetter].
  final LetterPosition position;

  List<ArabicLetter> get choices => choiceSet.choices;
  int get answerIndex => choiceSet.answerIndex;
}

/// Builds a round: targets don't repeat until the pool is used up, every
/// question has distinct choices and always contains the right answer.
List<LetterQuestion> generateLetterRound(
  LetterLevel level,
  math.Random rng, {
  int length = lettersRoundLength,
}) {
  final pool = level.pool;
  final questions = <LetterQuestion>[];
  var bag = <ArabicLetter>[];
  for (var i = 0; i < length; i++) {
    if (bag.isEmpty) bag = [...pool]..shuffle(rng);
    final target = bag.removeLast();
    final mode = level.modes[rng.nextInt(level.modes.length)];
    final positions = target.positions;
    final position = mode == LetterMode.formToLetter
        // Prefer the joined shapes: they are what the forms quiz is about.
        ? (positions.length > 1 ? positions[1 + rng.nextInt(positions.length - 1)] : positions.first)
        : LetterPosition.isolated;
    questions.add(LetterQuestion(
      mode: mode,
      target: target,
      position: position,
      choiceSet: buildChoices<ArabicLetter>(
        correct: target,
        pool: pool,
        count: level.choices,
        rng: rng,
        preferred: level.lookAlikes ? lookAlikesOf(target).where(pool.contains) : null,
      ),
    ));
  }
  return questions;
}
