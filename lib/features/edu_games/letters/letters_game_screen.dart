import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app_variant.dart';
import '../../../core/l10n_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/catalog/arabic_letters.dart';
import '../../../l10n/app_localizations.dart';
import '../../../router.dart';
import '../../../shared/widgets/zad_widgets.dart';
import '../edu_game_hooks.dart';
import '../quiz_core.dart';
import '../stars_controller.dart';
import '../widgets/edu_widgets.dart';
import 'letters_progress.dart';
import 'letters_quiz.dart';

/// حروف القرآن / Quran Letters.
class LettersGameScreen extends ConsumerStatefulWidget {
  const LettersGameScreen({super.key});

  @override
  ConsumerState<LettersGameScreen> createState() => _LettersGameScreenState();
}

enum _Phase { levels, playing, done }

class _LettersGameScreenState extends ConsumerState<LettersGameScreen> {
  final _rng = math.Random();
  _Phase _phase = _Phase.levels;
  LetterLevel _level = letterLevels.first;
  List<LetterQuestion> _questions = const [];
  int _index = 0;
  final Set<int> _tried = {};
  bool _solved = false;
  int _firstTry = 0;
  int _earned = 0;
  Timer? _advance;

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  void _start(LetterLevel level) {
    _advance?.cancel();
    setState(() {
      _level = level;
      _questions = generateLetterRound(level, _rng);
      _index = 0;
      _tried.clear();
      _solved = false;
      _firstTry = 0;
      _phase = _Phase.playing;
    });
  }

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
      _advance = Timer(const Duration(milliseconds: 1100), _next);
    } else {
      setState(() => _tried.add(i));
      hooks.onWrong();
    }
  }

  void _next() {
    if (!mounted) return;
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
    ref.read(lettersProgressProvider.notifier).record(_level.number, stars);
    final hooks = ref.read(eduGameHooksProvider);
    hooks.onRoundComplete(stars); // win combo
    hooks.onStarsEarned(stars); // then one coin ping per star
    setState(() {
      _earned = stars;
      _phase = _Phase.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return EduGameScaffold(
      title: l10n.zadGameLetters,
      tint: const Color(0xFFFFF9E6),
      child: switch (_phase) {
        _Phase.levels => _LevelList(onPick: _start),
        _Phase.playing => _buildQuestion(context),
        _Phase.done => CelebrationView(
            stars: _earned,
            firstTry: _firstTry,
            total: _questions.length,
            onPlayAgain: () => _start(_level),
            onBack: () => setState(() => _phase = _Phase.levels),
            // The mosque builder exists in Zad X Play only.
            onBuild: kIsKids ? null : () => context.pushReplacement(Routes.eduMasjid),
          ),
      },
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final q = _questions[_index];
    final prompt = switch (q.mode) {
      LetterMode.letterToName => l10n.lettersAskName,
      LetterMode.nameToLetter => l10n.lettersAskLetter(lang == 'ar' ? q.target.nameAr : q.target.nameEn),
      LetterMode.formToLetter => l10n.lettersAskForm(_positionText(l10n, q.position)),
    };
    final feedback = _solved ? l10n.eduWellDone : (_tried.isNotEmpty ? l10n.eduTryAgain : null);

    return ListView(padding: const EdgeInsets.all(16), children: [
      QuestionProgress(index: _index, total: _questions.length),
      const SizedBox(height: 14),
      ZadCard(
        child: Column(children: [
          Text(prompt, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Prompt(question: q, lang: lang),
        ]),
      ),
      const SizedBox(height: 6),
      FeedbackLine(text: feedback, positive: _solved),
      const SizedBox(height: 6),
      ChoiceGridLayout(children: [
        for (var i = 0; i < q.choices.length; i++)
          BigChoiceButton(
            look: _solved && i == q.answerIndex
                ? ChoiceLook.correct
                : (_tried.contains(i) ? ChoiceLook.tried : ChoiceLook.idle),
            onTap: () => _onChoice(i),
            semanticLabel: _choiceLabel(q.choices[i], lang),
            minHeight: q.mode == LetterMode.letterToName ? 80 : 104,
            child: q.mode == LetterMode.letterToName
                ? _NameLabel(letter: q.choices[i], lang: lang)
                : _Glyph(text: q.choices[i].char, size: 60),
          ),
      ]),
    ]);
  }

  String _choiceLabel(ArabicLetter l, String lang) =>
      lang == 'ar' ? l.nameAr : '${l.nameAr} (${l.nameEn})';

  static String _positionText(AppLocalizations l10n, LetterPosition p) => switch (p) {
        LetterPosition.isolated => l10n.lettersPosIsolated,
        LetterPosition.initial => l10n.lettersPosInitial,
        LetterPosition.medial => l10n.lettersPosMedial,
        LetterPosition.finalForm => l10n.lettersPosFinal,
      };
}

class _Prompt extends StatelessWidget {
  const _Prompt({required this.question, required this.lang});
  final LetterQuestion question;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final q = question;
    return switch (q.mode) {
      LetterMode.letterToName => _Glyph(text: q.target.char, size: 110),
      LetterMode.formToLetter => _Glyph(text: q.target.form(q.position), size: 110),
      LetterMode.nameToLetter => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: _NameLabel(letter: q.target, lang: lang, big: true),
        ),
    };
  }
}

/// An Arabic letter (or letter shape) drawn large in the Quran font.
class _Glyph extends StatelessWidget {
  const _Glyph({required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Text(
          text,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: AppTheme.quran(size, color: AppColors.navy).copyWith(height: 1.35),
        ),
      );
}

class _NameLabel extends StatelessWidget {
  const _NameLabel({required this.letter, required this.lang, this.big = false});
  final ArabicLetter letter;
  final String lang;
  final bool big;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            letter.nameAr,
            textDirection: TextDirection.rtl,
            style: AppTheme.display(big ? 44 : 28, color: AppColors.navy),
          ),
          if (lang != 'ar')
            Text(letter.nameEn, style: TextStyle(fontSize: big ? 20 : 15, color: AppColors.muted, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _LevelList extends ConsumerWidget {
  const _LevelList({required this.onPick});
  final ValueChanged<LetterLevel> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final best = ref.watch(lettersProgressProvider);
    final progress = ref.read(lettersProgressProvider.notifier);
    final descriptions = [l10n.lettersLevel1, l10n.lettersLevel2, l10n.lettersLevel3, l10n.lettersLevel4, l10n.lettersLevel5];

    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(l10n.eduChooseLevel, style: AppTheme.display(26, color: AppColors.purpleDark)),
      const SizedBox(height: 10),
      for (final level in letterLevels) ...[
        _LevelCard(
          title: l10n.eduLevelN(Fmt.digits(level.number, lang)),
          description: descriptions[(level.number - 1) % descriptions.length],
          stars: best[level.number] ?? 0,
          starsLabel: l10n.eduBestStars(Fmt.digits(best[level.number] ?? 0, lang), Fmt.digits(3, lang)),
          unlocked: progress.isUnlocked(level.number),
          lockedText: l10n.eduLevelLocked,
          onTap: () => onPick(level),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({
    required this.title,
    required this.description,
    required this.stars,
    required this.starsLabel,
    required this.unlocked,
    required this.lockedText,
    required this.onTap,
  });

  final String title;
  final String description;
  final int stars;
  final String starsLabel;
  final bool unlocked;
  final String lockedText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        enabled: unlocked,
        label: '$title. ${unlocked ? description : lockedText}. $starsLabel',
        onTap: unlocked ? onTap : null,
        excludeSemantics: true,
        child: Material(
          color: unlocked ? Colors.white : const Color(0xFFF1EFF6),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: unlocked ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: unlocked ? AppColors.yellow : const Color(0xFFDDD8EA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(unlocked ? Icons.play_arrow_rounded : Icons.lock_rounded, color: AppColors.ink, size: 30),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(unlocked ? description : lockedText, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
                    ]),
                  ),
                  StarsRow(count: stars, size: 22),
                ]),
              ),
            ),
          ),
        ),
      );
}
