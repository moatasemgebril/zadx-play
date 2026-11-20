import 'dart:math' as math;

import '../../../core/localized.dart';
import '../../../data/catalog/prophets_quiz.dart';
import '../quiz_core.dart';

const prophetsRoundLength = 6;

class ProphetRoundQuestion {
  const ProphetRoundQuestion(this.source, this.choiceSet);
  final ProphetQuestion source;
  final ChoiceSet<Localized> choiceSet;

  List<Localized> get choices => choiceSet.choices;
  int get answerIndex => choiceSet.answerIndex;
}

/// Picks [length] different questions and shuffles each one's answers.
List<ProphetRoundQuestion> generateProphetRound(
  math.Random rng, {
  int length = prophetsRoundLength,
  List<ProphetQuestion> bank = prophetQuestions,
}) {
  final picked = [...bank]..shuffle(rng);
  return [
    for (final q in picked.take(length))
      ProphetRoundQuestion(
        q,
        buildChoices<Localized>(correct: q.answer, pool: q.wrong, count: q.wrong.length + 1, rng: rng),
      ),
  ];
}
