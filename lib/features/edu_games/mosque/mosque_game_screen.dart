import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/catalog/mosque_parts.dart';
import '../../../router.dart';
import '../../../shared/widgets/zad_widgets.dart';
import '../edu_game_hooks.dart';
import '../stars_controller.dart';
import '../widgets/edu_widgets.dart';
import 'mosque_controller.dart';
import 'mosque_painter.dart';

/// ابنِ مسجدك / Build Your Mosque: spend stars to add parts.
class MosqueGameScreen extends ConsumerStatefulWidget {
  const MosqueGameScreen({super.key});

  @override
  ConsumerState<MosqueGameScreen> createState() => _MosqueGameScreenState();
}

class _MosqueGameScreenState extends ConsumerState<MosqueGameScreen> {
  /// The part whose kind line is shown (last built, or the one tapped).
  int? _shownPart;
  bool _justBuilt = false;

  void _build() {
    final result = ref.read(mosqueProvider.notifier).buildNext();
    if (result != BuildResult.built) return;
    ref.read(eduGameHooksProvider).onPartBuilt();
    final built = ref.read(mosqueProvider);
    if (built >= mosqueParts.length) ref.read(eduGameHooksProvider).onRoundComplete(3);
    setState(() {
      _shownPart = built - 1;
      _justBuilt = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final built = ref.watch(mosqueProvider);
    final stars = ref.watch(starsProvider);
    final complete = built >= mosqueParts.length;
    final next = complete ? null : mosqueParts[built];
    final shown = _shownPart ?? (built > 0 ? built - 1 : null);

    return EduGameScaffold(
      title: l10n.zadGameMasjid,
      tint: const Color(0xFFEDFAF4),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        ZadCard(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Semantics(
              image: true,
              label: l10n.mosquePartsDone(Fmt.digits(built, lang), Fmt.digits(mosqueParts.length, lang)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFBDEBFA), Color(0xFFE9F8FF)],
                    ),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1.1,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(built),
                      tween: Tween(begin: 0.96, end: 1),
                      // Reduce-motion: the new part simply appears.
                      duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) => Transform.scale(scale: v, child: child),
                      child: CustomPaint(painter: MosquePainter(built: built)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ProgressBar(value: built / mosqueParts.length, color: AppColors.mint),
            const SizedBox(height: 4),
            Text(
              l10n.mosquePartsDone(Fmt.digits(built, lang), Fmt.digits(mosqueParts.length, lang)),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.mintText),
            ),
          ]),
        ),
        if (shown != null) ...[
          const SizedBox(height: 12),
          _PartLine(
            title: _justBuilt && shown == built - 1
                ? l10n.mosqueBuiltPart(mosqueParts[shown].name.of(lang))
                : mosqueParts[shown].name.of(lang),
            line: mosqueParts[shown].line.of(lang),
          ),
        ],
        const SizedBox(height: 12),
        if (complete)
          ZadCard(
            child: Column(children: [
              const Icon(Icons.mosque_rounded, size: 48, color: AppColors.mint),
              Semantics(
                liveRegion: true,
                child: Text(l10n.mosqueComplete, textAlign: TextAlign.center, style: AppTheme.display(26, color: AppColors.mintText)),
              ),
            ]),
          )
        else
          _NextPartCard(part: next!, stars: stars, onBuild: _build),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < mosqueParts.length; i++)
            _PartChip(
              label: mosqueParts[i].name.of(lang),
              built: i < built,
              selected: i == shown,
              onTap: i < built
                  ? () => setState(() {
                        _shownPart = i;
                        _justBuilt = false;
                      })
                  : null,
            ),
        ]),
      ]),
    );
  }
}

class _NextPartCard extends StatelessWidget {
  const _NextPartCard({required this.part, required this.stars, required this.onBuild});
  final MosquePart part;
  final int stars;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final canBuild = stars >= part.cost;
    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.mosqueNext(part.name.of(lang)), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.star_rounded, color: AppColors.yellow, size: 24),
          const SizedBox(width: 4),
          Text(l10n.mosqueCost(Fmt.digits(part.cost, lang)), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: canBuild ? onBuild : null,
          icon: const Icon(Icons.construction_rounded),
          label: Text(l10n.mosqueBuild),
        ),
        if (!canBuild) ...[
          const SizedBox(height: 10),
          Text(
            l10n.mosqueNeedStars(Fmt.digits(part.cost - stars, lang)),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: AppColors.purpleDark, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => context.pushReplacement(Routes.eduLetters),
                child: Text(l10n.zadGameLetters, textAlign: TextAlign.center),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => context.pushReplacement(Routes.eduProphets),
                child: Text(l10n.zadGameProphets, textAlign: TextAlign.center),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _PartLine extends StatelessWidget {
  const _PartLine({required this.title, required this.line});
  final String title;
  final String line;

  @override
  Widget build(BuildContext context) => Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.mintSoft, borderRadius: BorderRadius.circular(18)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.lightbulb_rounded, color: AppColors.mintText, size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.mintText)),
                const SizedBox(height: 2),
                Text(line, style: const TextStyle(fontSize: 16, color: AppColors.ink)),
              ]),
            ),
          ]),
        ),
      );
}

class _PartChip extends StatelessWidget {
  const _PartChip({required this.label, required this.built, required this.selected, this.onTap});
  final String label;
  final bool built;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        selected: selected,
        child: Material(
          color: selected ? AppColors.mintText : (built ? AppColors.mintSoft : Colors.white),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    built ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: selected ? Colors.white : (built ? AppColors.mintText : AppColors.muted),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : (built ? AppColors.mintText : AppColors.muted),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}
