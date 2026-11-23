import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../router.dart';
import '../../../shared/art/zad_art.dart';
import '../../../shared/widgets/zad_widgets.dart';
import '../stars_controller.dart';

/// Full-screen frame for a Zad X learning game: app bar with the star balance
/// and the games scene. The scene stays still here (no motion) so it never
/// competes with the question the child is reading.
///
/// [tint] is kept for API compatibility; the scene now sets the colours.
///
/// The app bar always has an "Exit game" button: children leave a game freely,
/// with no confirmation, even when the game was opened without a page behind it.
class EduGameScaffold extends StatelessWidget {
  const EduGameScaffold({super.key, required this.title, required this.child, this.tint = const Color(0xFFF4EEFF)});

  final String title;
  final Widget child;
  final Color tint;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          leading: IconButton(
            key: const Key('eduExitGame'),
            tooltip: context.l10n.eduExitGame,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const BackButtonIcon(),
            onPressed: () => exitEduGame(context),
          ),
          title: Text(title, style: AppTheme.display(22, color: Colors.white)),
          actions: const [StarBalanceChip(), SizedBox(width: 12)],
        ),
        body: ZadSceneBackground(scene: ZadScene.games, animate: false, child: SafeArea(child: child)),
      );
}

/// Leaves a learning game: back to the previous page, or to the games hub when
/// there is none (e.g. the game was opened from a link).
void exitEduGame(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) {
    Navigator.maybePop(context);
  } else if (router.canPop()) {
    router.pop();
  } else {
    router.go(Routes.games);
  }
}

class StarBalanceChip extends ConsumerWidget {
  const StarBalanceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stars = ref.watch(starsProvider);
    final text = Fmt.digits(stars, context.lang);
    return Semantics(
      label: context.l10n.eduStarsLabel(text),
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const ZadIcon(ZadIconKind.star, size: 24),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

/// Visual state of an answer button.
enum ChoiceLook { idle, correct, tried }

/// A big answer button (never under 48 × 48 dp). Wrong answers turn soft grey —
/// never red — so mistakes feel gentle.
///
/// The state never relies on colour alone: a correct answer shows a tick, a
/// tried one a "try again" arrow, and screen readers hear the state after the
/// answer (`eduChoiceCorrect` / `eduChoiceTried` strings).
class BigChoiceButton extends StatelessWidget {
  const BigChoiceButton({
    super.key,
    required this.child,
    required this.look,
    required this.onTap,
    required this.semanticLabel,
    this.minHeight = 72,
  });

  final Widget child;
  final ChoiceLook look;
  final VoidCallback? onTap;
  final String semanticLabel;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final (bg, border) = switch (look) {
      ChoiceLook.idle => (Colors.white, AppColors.purple),
      ChoiceLook.correct => (AppColors.mintSoft, AppColors.mint),
      ChoiceLook.tried => (const Color(0xFFF1EFF6), const Color(0xFFD9D4E8)),
    };
    final l10n = context.l10n;
    final label = switch (look) {
      ChoiceLook.idle => semanticLabel,
      ChoiceLook.correct => l10n.eduChoiceCorrect(semanticLabel),
      ChoiceLook.tried => l10n.eduChoiceTried(semanticLabel),
    };
    return Semantics(
      container: true,
      button: true,
      label: label,
      selected: look == ChoiceLook.correct,
      onTap: onTap,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: look == ChoiceLook.correct ? 1.05 : 1,
        // Reduce-motion: no grow effect.
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: border, width: 2.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: math.max(minHeight, 48), minWidth: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Stack(alignment: Alignment.center, children: [
                  Opacity(opacity: look == ChoiceLook.tried ? 0.55 : 1, child: Center(child: child)),
                  if (look == ChoiceLook.correct)
                    const PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: Icon(Icons.check_circle_rounded, key: Key('choiceCorrectMark'), color: AppColors.mint, size: 26),
                    ),
                  if (look == ChoiceLook.tried)
                    const PositionedDirectional(
                      top: 0,
                      end: 0,
                      child: Icon(Icons.replay_rounded, key: Key('choiceTriedMark'), color: AppColors.purpleDark, size: 24),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lays out answer buttons in [columns] equal columns.
class ChoiceGridLayout extends StatelessWidget {
  const ChoiceGridLayout({super.key, required this.children, this.columns = 2, this.gap = 12});

  final List<Widget> children;
  final int columns;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.center,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      });
}

/// Short, kind feedback under the question: an icon plus text, so the meaning
/// never depends on colour alone.
class FeedbackLine extends StatelessWidget {
  const FeedbackLine({super.key, required this.text, required this.positive});
  final String? text;
  final bool positive;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: text == null
              ? const SizedBox.shrink()
              : Semantics(
                  key: ValueKey(text),
                  liveRegion: true,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(
                      positive ? Icons.check_circle_rounded : Icons.replay_rounded,
                      key: Key(positive ? 'feedbackCorrectIcon' : 'feedbackTryAgainIcon'),
                      color: positive ? AppColors.mintText : AppColors.purpleDark,
                      size: 24,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        text!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: positive ? AppColors.mintText : AppColors.purpleDark,
                        ),
                      ),
                    ),
                  ]),
                ),
        ),
      );
}

class StarsRow extends StatelessWidget {
  const StarsRow({super.key, required this.count, this.total = 3, this.size = 28});
  final int count;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < total; i++)
            Icon(
              i < count ? Icons.star_rounded : Icons.star_outline_rounded,
              color: i < count ? AppColors.yellow : const Color(0xFFC9C2E6),
              size: size,
            ),
        ]),
      );
}

class QuestionProgress extends StatelessWidget {
  const QuestionProgress({super.key, required this.index, required this.total});
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
        context.l10n.eduQuestionOf(Fmt.digits(index + 1, lang), Fmt.digits(total, lang)),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.purpleDark),
      ),
      const SizedBox(height: 6),
      ProgressBar(value: (index + 1) / total, color: AppColors.purple),
    ]);
  }
}

/// Shown after every round: stars pop in, a kind message, and next steps.
class CelebrationView extends StatelessWidget {
  const CelebrationView({
    super.key,
    required this.stars,
    required this.firstTry,
    required this.total,
    required this.onPlayAgain,
    required this.onBack,
    this.onBuild,
  });

  final int stars;
  final int firstTry;
  final int total;
  final VoidCallback onPlayAgain;
  final VoidCallback onBack;
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    return ListView(padding: const EdgeInsets.all(20), children: [
      ZadCard(
        padding: const EdgeInsets.all(22),
        child: Column(children: [
          SizedBox(
            height: 150,
            child: Stack(alignment: Alignment.center, children: [
              const Positioned.fill(child: ExcludeSemantics(child: CustomPaint(painter: _SparklePainter()))),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.2, end: 1),
                // Reduce-motion: the stars simply appear.
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 900),
                curve: Curves.elasticOut,
                builder: (context, v, child) => Transform.scale(scale: v, child: child),
                child: StarsRow(count: stars, size: 64),
              ),
              // A short star burst for the stars just earned.
              const Positioned.fill(child: ZadCelebrationBurst(origin: Alignment.center)),
            ]),
          ),
          Semantics(
            liveRegion: true,
            child: Text(l10n.eduRoundDone, textAlign: TextAlign.center, style: AppTheme.display(28, color: AppColors.purpleDark)),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.eduStarsEarned(Fmt.digits(stars, lang)),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
          ),
          Text(
            l10n.eduFirstTry(Fmt.digits(firstTry, lang), Fmt.digits(total, lang)),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.muted),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: onPlayAgain,
        icon: const Icon(Icons.replay_rounded),
        label: Text(l10n.eduPlayAgain),
      ),
      if (onBuild != null) ...[
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            backgroundColor: AppColors.yellow,
            foregroundColor: AppColors.ink,
          ),
          onPressed: onBuild,
          icon: const Icon(Icons.mosque_rounded),
          label: Text(l10n.eduGoBuild),
        ),
      ],
      const SizedBox(height: 10),
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        onPressed: onBack,
        child: Text(l10n.eduBackToGames),
      ),
    ]);
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter();

  static const _colors = [AppColors.yellow, AppColors.sky, AppColors.coral, AppColors.mint, AppColors.purple];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (var i = 0; i < 14; i++) {
      final a = i * math.pi * 2 / 14;
      final r = size.shortestSide * (i.isEven ? 0.42 : 0.32);
      final p = c + Offset(math.cos(a) * r * 1.6, math.sin(a) * r);
      canvas.drawCircle(p, i.isEven ? 5 : 3.5, Paint()..color = _colors[i % _colors.length].withValues(alpha: 0.7));
    }
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) => false;
}

/// Small parent-facing note shown while religious content is unreviewed.
class ParentReviewNote extends StatelessWidget {
  const ParentReviewNote({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppColors.pendingBg, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: AppColors.pendingText, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              context.l10n.parentReviewNote,
              style: const TextStyle(fontSize: 13, color: AppColors.pendingText, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );
}
