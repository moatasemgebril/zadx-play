import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/catalog/prophets_quiz.dart';
import '../../../router.dart';
import '../../../shared/widgets/zad_widgets.dart';
import '../edu_game_hooks.dart';
import '../quiz_core.dart';
import '../stars_controller.dart';
import '../widgets/edu_widgets.dart';
import 'prophets_quiz_logic.dart';
import 'scene_painter.dart';

/// أبطال الأنبياء / Heroes of the Prophets — a story quiz.
///
/// Prophets are never depicted: each question shows scenery/objects only.
class ProphetsGameScreen extends ConsumerStatefulWidget {
  const ProphetsGameScreen({super.key});

  @override
  ConsumerState<ProphetsGameScreen> createState() => _ProphetsGameScreenState();
}

enum _Phase { intro, playing, done }

class _ProphetsGameScreenState extends ConsumerState<ProphetsGameScreen> {
  final _rng = math.Random();
  _Phase _phase = _Phase.intro;
  List<ProphetRoundQuestion> _questions = const [];
  int _index = 0;
  final Set<int> _tried = {};
  bool _solved = false;
  int _firstTry = 0;
  int _earned = 0;

  void _start() => setState(() {
        _questions = generateProphetRound(_rng);
        _index = 0;
        _tried.clear();
        _solved = false;
        _firstTry = 0;
        _phase = _Phase.playing;
      });

  void _onChoice(int i) {
    final q = _questions[_index];
    if (_solved || _tried.contains(i)) return;
    final hooks = ref.read(eduGameHooksProvider);
    if (i == q.answerIndex) {
      setState(() {
        _solved = true;
        if (_tried.isEmpty) _firstTry++;
      });
      hooks.onCorrect();
    } else {
      setState(() => _tried.add(i));
      hooks.onWrong();
    }
  }

  void _next() {
    if (_index + 1 < _questions.length) {
      setState(() {
        _index++;
        _tried.clear();
        _solved = false;
      });
      return;
    }
    final stars = starsForRound(firstTryCorrect: _firstTry, total: _questions.length);
    ref.read(starsProvider.notifier).earn(stars);
    ref.read(eduGameHooksProvider).onRoundComplete(stars);
    setState(() {
      _earned = stars;
      _phase = _Phase.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EduGameScaffold(
      title: l10n.zadGameProphets,
      tint: const Color(0xFFEAF8FD),
      child: switch (_phase) {
        _Phase.intro => _Intro(onStart: _start),
        _Phase.playing => _buildQuestion(context),
        _Phase.done => CelebrationView(
            stars: _earned,
            firstTry: _firstTry,
            total: _questions.length,
            onPlayAgain: _start,
            onBack: () => context.pop(),
            onBuild: () => context.pushReplacement(Routes.eduMasjid),
          ),
      },
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final rq = _questions[_index];
    final q = rq.source;
    final feedback = _solved ? l10n.eduWellDone : (_tried.isNotEmpty ? l10n.eduTryAgain : null);

    return ListView(padding: const EdgeInsets.all(16), children: [
      QuestionProgress(index: _index, total: _questions.length),
      const SizedBox(height: 12),
      ZadCard(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: ExcludeSemantics(
              child: SizedBox(
                height: 170,
                width: double.infinity,
                child: CustomPaint(painter: ProphetScenePainter(q.scene)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(q.question.of(lang), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
        ]),
      ),
      const SizedBox(height: 4),
      FeedbackLine(text: feedback, positive: _solved),
      const SizedBox(height: 4),
      for (var i = 0; i < rq.choices.length; i++) ...[
        BigChoiceButton(
          look: _solved && i == rq.answerIndex
              ? ChoiceLook.correct
              : (_tried.contains(i) ? ChoiceLook.tried : ChoiceLook.idle),
          onTap: () => _onChoice(i),
          semanticLabel: rq.choices[i].of(lang),
          minHeight: 64,
          child: Text(
            rq.choices[i].of(lang),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.navy),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (_solved) ...[
        _FactCard(question: q),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _next,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(l10n.eduNext),
        ),
      ],
      if (!reviewedByScholar) ...[const SizedBox(height: 16), const ParentReviewNote()],
    ]);
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(padding: const EdgeInsets.all(16), children: [
      ZadCard(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            child: ExcludeSemantics(
              child: SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(painter: ProphetScenePainter(ProphetScene.night)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(l10n.zadGameProphets, style: AppTheme.display(28, color: AppColors.purpleDark)),
          Text(l10n.prophetsIntro, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: AppColors.muted)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(l10n.play),
          ),
        ]),
      ),
      if (!reviewedByScholar) ...[const SizedBox(height: 16), const ParentReviewNote()],
    ]);
  }
}

class _FactCard extends StatelessWidget {
  const _FactCard({required this.question});
  final ProphetQuestion question;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.mintSoft, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.menu_book_rounded, color: AppColors.mintText, size: 24),
            const SizedBox(width: 6),
            Text(l10n.prophetsDidYouKnow, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.mintText)),
          ]),
          const SizedBox(height: 6),
          Text(question.fact.of(lang), style: const TextStyle(fontSize: 17, color: AppColors.ink)),
          const SizedBox(height: 6),
          for (final ref in question.refs)
            Text(
              l10n.prophetsRef(ref.surahName.of(lang), Fmt.digits(ref.citation, lang)),
              style: const TextStyle(fontSize: 14, color: AppColors.mintText, fontWeight: FontWeight.w700),
            ),
        ]),
      ),
    );
  }
}
