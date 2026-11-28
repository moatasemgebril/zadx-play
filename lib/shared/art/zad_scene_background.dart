import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import 'art_shapes.dart';
import 'scene_palettes.dart';
import 'scenes/brand_backdrop.dart';
import 'scenes/games_scene.dart';
import 'scenes/home_scene.dart';
import 'scenes/night_scene.dart';
import 'scenes/parent_scene.dart';
import 'scenes/prayer_sky.dart';
import 'scenes/tasks_scene.dart';

/// The background mood of each area of the app.
enum ZadScene {
  /// Sunrise sky over a little town with a mosque (Zad X Kids: a treehouse oak instead).
  home,

  /// Floating islands, bright but calm.
  games,

  /// A garden that grows with today's tasks.
  tasks,

  /// Quran & Adhkar: calm night sky, crescent, stars, lanterns.
  /// Never shown in Zad X Kids; there it would paint a neutral space sky (full moon, planet, rocket).
  quran,

  /// Sky that follows the prayer day (see [PrayerSkyPhase]).
  /// Never shown in Zad X Kids; there it has a full moon and a little house, no crescent or dome.
  prayer,

  /// Parent area, settings, help, subscription. Zad X Play: the brand navy backdrop
  /// (owner decision 2026-11-27); Zad X Kids: a light grid of rounded squares and dots.
  parent,
}

extension ZadSceneInfo on ZadScene {
  ScenePalette get palette => switch (this) {
        ZadScene.home => ScenePalettes.home,
        ZadScene.games => ScenePalettes.games,
        ZadScene.tasks => ScenePalettes.tasks,
        ZadScene.quran => ScenePalettes.quran,
        ZadScene.prayer => ScenePalettes.prayer,
        ZadScene.parent => artReligiousMotifs ? ScenePalettes.parentBrand : ScenePalettes.parent,
      };

  /// Colour of headings placed directly on this scene (not inside a card).
  Color get titleColor => palette.dark ? AppColors.onNavy : AppColors.ink;

  /// Colour of body / note text placed directly on this scene (not inside a card).
  Color get bodyColor => palette.dark ? AppColors.onNavyMuted : AppColors.muted;

  /// Length of one seamless loop. Calmer areas loop more slowly.
  Duration? get loop => switch (this) {
        ZadScene.home => const Duration(seconds: 40),
        ZadScene.games => const Duration(seconds: 24),
        ZadScene.tasks => const Duration(seconds: 20),
        ZadScene.quran => const Duration(seconds: 48),
        ZadScene.prayer => const Duration(seconds: 40),
        ZadScene.parent => null, // professional: no motion at all
      };
}

/// Original, code-drawn background for a whole screen area.
///
/// Layers (bottom → top): static scene, gentle looping motion, readability
/// scrim, then [child]. Each art layer sits in its own [RepaintBoundary] and
/// ignores pointers and semantics. Motion:
/// * stops on a static frame when the system asks to reduce motion
///   ([MediaQuery.disableAnimations]) or when [animate] is false;
/// * pauses automatically when the screen is off-stage (inactive tab, covered
///   route), because tickers are muted by [TickerMode];
/// * never flashes: changes are slow alpha/position waves (≤ 1 cycle/s).
///
/// RTL: the scene is mirrored so its focal point (sun, moon) sits on the
/// trailing side, away from where headings start.
class ZadSceneBackground extends StatefulWidget {
  const ZadSceneBackground({
    super.key,
    required this.scene,
    required this.child,
    this.progress = 0,
    this.prayerPhase = PrayerSkyPhase.day,
    this.animate = true,
  });

  final ZadScene scene;
  final Widget child;

  /// Tasks only: share of today's tasks that are done (0..1). Read-only input.
  final double progress;

  /// Prayer only: which sky to show.
  final PrayerSkyPhase prayerPhase;

  /// Set false for busy screens (e.g. quiz questions) to keep a still frame.
  final bool animate;

  @override
  State<ZadSceneBackground> createState() => _ZadSceneBackgroundState();
}

class _ZadSceneBackgroundState extends State<ZadSceneBackground> with SingleTickerProviderStateMixin {
  /// The still frame shown with reduce-motion (chosen so clouds and
  /// balloons are nicely spread out).
  static const _stillFrame = 0.15;

  late final AnimationController _motion = AnimationController(vsync: this, value: _stillFrame);

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(ZadSceneBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene != widget.scene || oldWidget.animate != widget.animate) _syncMotion();
  }

  void _syncMotion() {
    final loop = widget.scene.loop;
    final shouldMove = widget.animate && loop != null && !_reduceMotion;
    if (shouldMove) {
      if (_motion.duration != loop) _motion.duration = loop;
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = _stillFrame;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  (CustomPainter, CustomPainter?) _painters() {
    final t = _motion.view;
    return switch (widget.scene) {
      ZadScene.home => (const HomeStaticPainter(), HomeMotionPainter(t)),
      ZadScene.games => (const GamesStaticPainter(), GamesMotionPainter(t)),
      ZadScene.tasks => (
          const TasksStaticPainter(),
          TasksMotionPainter(t, blooms: gardenBloomCount(widget.progress)),
        ),
      ZadScene.quran => (const NightStaticPainter(), NightMotionPainter(t)),
      ZadScene.prayer => (PrayerSkyStaticPainter(widget.prayerPhase), PrayerSkyMotionPainter(t, widget.prayerPhase)),
      ZadScene.parent => (artReligiousMotifs ? const BrandBackdropPainter() : const ParentStaticPainter(), null),
    };
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    final (still, moving) = _painters();
    final scrim = widget.scene.palette.scrim;

    Widget layer(CustomPainter painter, {required bool changes}) => Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: RepaintBoundary(
                child: Transform.flip(
                  flipX: rtl,
                  child: CustomPaint(painter: painter, isComplex: true, willChange: changes),
                ),
              ),
            ),
          ),
        );

    return Stack(children: [
      layer(still, changes: false),
      if (moving != null) layer(moving, changes: true),
      if (scrim.a > 0) Positioned.fill(child: IgnorePointer(child: ColoredBox(color: scrim))),
      widget.child,
    ]);
  }
}
