import 'dart:math' as math;

/// Number of stars (1–3) for a finished round. Finishing always earns at
/// least one star: the games reward effort, never punish.
int starsForRound({required int firstTryCorrect, required int total}) {
  if (total <= 0) return 1;
  final ratio = firstTryCorrect / total;
  if (ratio >= 0.85) return 3;
  if (ratio >= 0.5) return 2;
  return 1;
}

/// A multiple-choice question: [choices] are distinct and contain the answer
/// at [answerIndex].
class ChoiceSet<T> {
  const ChoiceSet(this.choices, this.answerIndex);
  final List<T> choices;
  final int answerIndex;

  T get answer => choices[answerIndex];
}

/// Picks `count - 1` distinct distractors from [pool] (never equal to
/// [correct], never repeated), adds [correct] and shuffles.
///
/// [preferred] distractors (e.g. look-alike letters) are used first. If the
/// pool is too small the set is shorter, but it always holds the answer and
/// never holds duplicates.
ChoiceSet<T> buildChoices<T>({
  required T correct,
  required Iterable<T> pool,
  required int count,
  required math.Random rng,
  Iterable<T>? preferred,
}) {
  final picked = <T>[];
  void takeFrom(Iterable<T> source) {
    final candidates = source.where((e) => e != correct && !picked.contains(e)).toSet().toList()..shuffle(rng);
    for (final c in candidates) {
      if (picked.length >= count - 1) return;
      picked.add(c);
    }
  }

  if (preferred != null) takeFrom(preferred);
  takeFrom(pool);
  final choices = [...picked, correct]..shuffle(rng);
  return ChoiceSet(choices, choices.indexOf(correct));
}
