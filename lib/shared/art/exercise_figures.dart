import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'art_shapes.dart';

/// Original, code-drawn cartoon kids doing the light exercises in Tasks.
///
/// Design rules (kids art director, 2026-11-21):
/// - Original art only: simple rounded limbs on a 100×100 grid, drawn in
///   Dart. No bitmaps, no copied characters or styles.
/// - Modest and inclusive: long sleeves, long trousers, a neutral cap. The
///   head is a smooth shape with **no face** (no eyes or mouth), which suits
///   every family. No religious figures.
/// - Readable at 56–72 dp: one clear silhouette per move, the outfit in the
///   exercise colour, a soft darker outline and a floor shadow.
/// - Motion: one eased loop between two key poses (~1.2 s per rep). With
///   reduce-motion on (`MediaQuery.disableAnimations`) nothing moves: a
///   single still pose is shown and no ticker runs.
enum ExerciseMove {
  pushup(Color(0xFFFF6B6B), stillPose: 0.0, mat: true),
  situp(Color(0xFF4CC9F0), stillPose: 0.6, mat: true),
  jacks(Color(0xFFFFC83D), stillPose: 1.0, front: true),
  squat(Color(0xFF2DBE7E), stillPose: 0.8),
  toes(Color(0xFFC4B5FD), stillPose: 0.85),

  /// Fallback for exercises without their own drawing: a gentle arm stretch.
  generic(Color(0xFF6C3BEB), stillPose: 1.0, front: true);

  const ExerciseMove(this.color, {required this.stillPose, this.front = false, this.mat = false});

  /// Default outfit colour (the catalogue colour of the exercise).
  final Color color;

  /// Where between the two key poses (0..1) the still picture sits; chosen
  /// so the still frame reads clearly as the exercise.
  final double stillPose;

  /// Drawn facing the viewer (both sides alike) instead of side-on.
  final bool front;

  /// Floor exercise: draw a small mat under the figure.
  final bool mat;
}

/// Maps a task id from the catalogue (`default_tasks.dart`) to its drawing.
/// Unknown ids get [ExerciseMove.generic].
ExerciseMove exerciseMoveFor(String taskId) => switch (taskId) {
      'pushup' => ExerciseMove.pushup,
      'situp' => ExerciseMove.situp,
      'jacks' => ExerciseMove.jacks,
      'squat' => ExerciseMove.squat,
      'toes' => ExerciseMove.toes,
      _ => ExerciseMove.generic,
    };

/// Still figure for small or list use. Decorative (hidden from screen
/// readers: the exercise title is always next to it). Mirrored in RTL so the
/// figure faces the text.
class ExerciseFigure extends StatelessWidget {
  const ExerciseFigure({super.key, required this.taskId, this.color, this.size = 56});

  final String taskId;

  /// Outfit colour; defaults to the move's catalogue colour.
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final move = exerciseMoveFor(taskId);
    return _FigureFrame(
      size: size,
      painter: ExerciseFigurePainter(move: move, color: color ?? move.color),
    );
  }
}

/// Animated figure for the exercise card: loops the movement (one rep per
/// [repDuration], eased). When [reps] goes up (the child tapped "+1") the
/// figure does a small happy hop with three gold sparkles.
///
/// Reduce-motion or [animate] false → the still pose, no ticker. Tickers are
/// muted automatically on inactive tabs and covered routes (`TickerMode`), and
/// list items outside the viewport are not built, so off-screen figures cost
/// nothing.
class AnimatedExerciseFigure extends StatefulWidget {
  const AnimatedExerciseFigure({
    super.key,
    required this.taskId,
    this.color,
    this.size = 64,
    this.reps = 0,
    this.animate = true,
  });

  static const repDuration = Duration(milliseconds: 1200);
  static const hopDuration = Duration(milliseconds: 420);

  final String taskId;
  final Color? color;
  final double size;

  /// Reps counted so far; an increase plays the hop.
  final int reps;

  /// False shows the still pose (e.g. exercise already handed in).
  final bool animate;

  @override
  State<AnimatedExerciseFigure> createState() => _AnimatedExerciseFigureState();
}

class _AnimatedExerciseFigureState extends State<AnimatedExerciseFigure> with TickerProviderStateMixin {
  late final AnimationController _cycle = AnimationController(vsync: this, duration: AnimatedExerciseFigure.repDuration);
  late final AnimationController _hop = AnimationController(vsync: this, duration: AnimatedExerciseFigure.hopDuration);
  bool _reduceMotion = false;

  bool get _moving => widget.animate && !_reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(AnimatedExerciseFigure oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
    if (_moving && widget.reps > oldWidget.reps) _hop.forward(from: 0);
  }

  void _sync() {
    if (_moving) {
      if (!_cycle.isAnimating) _cycle.repeat();
    } else {
      _cycle
        ..stop()
        ..value = 0;
      _hop
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _cycle.dispose();
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final move = exerciseMoveFor(widget.taskId);
    final moving = _moving;
    return _FigureFrame(
      size: widget.size,
      painter: ExerciseFigurePainter(
        move: move,
        color: widget.color ?? move.color,
        cycle: moving ? _cycle : null,
        hop: moving ? _hop : null,
      ),
    );
  }
}

class _FigureFrame extends StatelessWidget {
  const _FigureFrame({required this.size, required this.painter});
  final double size;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    final rtl = (Directionality.maybeOf(context) ?? TextDirection.ltr) == TextDirection.rtl;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: Transform.flip(
            flipX: rtl,
            child: CustomPaint(size: Size.square(size), painter: painter),
          ),
        ),
      ),
    );
  }
}

/// Paints one exercise figure. With [cycle] it follows the animation
/// (repaints without widget rebuilds); without it, it paints the still pose.
class ExerciseFigurePainter extends CustomPainter {
  ExerciseFigurePainter({required this.move, required this.color, this.cycle, this.hop})
      : super(repaint: Listenable.merge([cycle, hop]));

  final ExerciseMove move;
  final Color color;
  final Animation<double>? cycle;
  final Animation<double>? hop;

  static const _ink = Color(0xFF1F1A3D);
  static const _gold = Color(0xFFFFC83D);
  static const _purple = Color(0xFF6C3BEB);
  static const _skin = Color(0xFFE6B48A);
  static const _skinLine = Color(0xFFA8714A);
  static const _trousers = Color(0xFF3B3F78);
  static const _shoe = Color(0xFFFFFFFF);

  static const _limb = 6.5;
  static const _torso = 14.0;
  static const _line = 1.7;
  static const _headR = 9.0;
  static const _floorY = 89.0;

  /// Pose progress 0..1 between the two key poses.
  double get poseT {
    final c = cycle;
    if (c == null) return move.stillPose;
    return 0.5 - 0.5 * math.cos(2 * math.pi * c.value);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width, size.height) / 100;
    if (s <= 0) return;
    final frames = _keyframes[move]!;
    final pose = _Pose.lerp(frames.$1, frames.$2, poseT);
    final up = hop == null ? 0.0 : math.sin(math.pi * hop!.value.clamp(0.0, 1.0));

    canvas.save();
    canvas.translate((size.width - 100 * s) / 2, (size.height - 100 * s) / 2);
    canvas.scale(s);

    // Mat and floor shadow.
    if (move.mat) {
      canvas.drawRRect(
        RRect.fromLTRBR(6, 86.5, 94, 91, const Radius.circular(2.2)),
        Paint()..color = color.withValues(alpha: 0.3),
      );
    }
    var minX = 100.0;
    var maxX = 0.0;
    for (final p in pose.points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
    }
    final shadowW = ((maxX - minX) + 8) * (1 - 0.15 * up);
    canvas.drawOval(
      Rect.fromCenter(center: Offset((minX + maxX) / 2, _floorY), width: shadowW, height: 5),
      Paint()..color = _ink.withValues(alpha: 0.13),
    );

    // Happy hop after "+1".
    canvas.save();
    if (up > 0) {
      canvas.translate(50, _floorY);
      canvas.scale(1 + 0.06 * up);
      canvas.translate(-50, -_floorY - 5 * up);
    }
    _paintFigure(canvas, pose);
    canvas.restore();

    if (up > 0) {
      final sparkle = Paint()..color = _gold.withValues(alpha: up);
      for (final c in const [Offset(82, 16), Offset(90, 32), Offset(70, 6)]) {
        canvas.drawPath(ArtShapes.sparkle(c, 3.5 + 2.5 * up), sparkle);
      }
    }
    canvas.restore();
  }

  void _paintFigure(Canvas canvas, _Pose pose) {
    final p = pose.points;
    final outline = Color.lerp(color, _ink, 0.5)!;
    final backColor = move.front ? color : Color.lerp(color, _ink, 0.18)!;
    final backTrousers = move.front ? _trousers : Color.lerp(_trousers, _ink, 0.3)!;

    void limb(List<Offset> pts, Color fill, Color line, double w) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final pt in pts.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint
        ..color = line
        ..strokeWidth = w + _line * 2);
      canvas.drawPath(path, paint
        ..color = fill
        ..strokeWidth = w);
    }

    void dot(Offset c, double r, Color fill, Color line) {
      canvas.drawCircle(c, r + _line, Paint()..color = line);
      canvas.drawCircle(c, r, Paint()..color = fill);
    }

    void shoe(Offset foot) {
      final rect = move.front
          ? Rect.fromCenter(center: foot, width: 7, height: 5)
          : Rect.fromCenter(center: foot + const Offset(2.5, 0), width: 9.5, height: 5);
      final r = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
      canvas.drawRRect(r.inflate(_line), Paint()..color = _ink);
      canvas.drawRRect(r, Paint()..color = _shoe);
    }

    void arm(int shoulder, Color fill) {
      limb([p[shoulder], p[shoulder + 1], p[shoulder + 2]], fill, outline, _limb);
      dot(p[shoulder + 2], 3.2, _skin, _skinLine);
    }

    void leg(int hip, Color fill) {
      limb([p[hip], p[hip + 1], p[hip + 2]], fill, _ink, _limb + 0.5);
      shoe(p[hip + 2]);
    }

    // Back side first, then torso, then the front side and the head.
    arm(_Pose.shoulderBack, backColor);
    leg(_Pose.hipBack, backTrousers);
    leg(_Pose.hipFront, _trousers);
    limb([p[_Pose.neck], p[_Pose.hip]], color, outline, _torso);
    arm(_Pose.shoulderFront, color);
    _paintHead(canvas, p[_Pose.head], p[_Pose.neck]);
  }

  /// Smooth faceless head with a neutral cap. The cap's brim points where the
  /// child is looking (floor in a push-up, sky when lying on the back).
  void _paintHead(Canvas canvas, Offset head, Offset neck) {
    final d = head - neck;
    final angle = math.atan2(d.dy, d.dx) + math.pi / 2;
    final cap = color == _gold ? _purple : _gold;
    final capLine = Color.lerp(cap, _ink, 0.45)!;

    canvas.save();
    canvas.translate(head.dx, head.dy);
    canvas.rotate(angle);
    const r = _headR;
    canvas.drawCircle(Offset.zero, r + _line, Paint()..color = _skinLine);
    canvas.drawCircle(Offset.zero, r, Paint()..color = _skin);

    final dome = Path()
      ..addArc(Rect.fromCircle(center: const Offset(0, -0.6), radius: r + 0.6), math.pi, math.pi)
      ..close();
    canvas.drawPath(dome, Paint()
      ..color = capLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = _line * 2
      ..strokeJoin = StrokeJoin.round);
    canvas.drawPath(dome, Paint()..color = cap);
    if (!move.front) {
      final brim = RRect.fromLTRBR(r * 0.2, -r * 0.2, r * 1.5, r * 0.12, const Radius.circular(1.6));
      canvas.drawRRect(brim.inflate(_line * 0.8), Paint()..color = capLine);
      canvas.drawRRect(brim, Paint()..color = cap);
    }
    // Soft shine on the cap (no facial features anywhere).
    canvas.drawCircle(const Offset(-r * 0.35, -r * 0.55), r * 0.18, Paint()..color = const Color(0x66FFFFFF));
    canvas.restore();
  }

  @override
  bool shouldRepaint(ExerciseFigurePainter oldDelegate) =>
      oldDelegate.move != move || oldDelegate.color != color || oldDelegate.cycle != cycle || oldDelegate.hop != hop;
}

/// A pose on the 100×100 grid (y down, floor at 88). Side-view figures face
/// to the right (the widget mirrors them in RTL).
@immutable
class _Pose {
  const _Pose(this.points);

  static const head = 0;
  static const neck = 1;
  static const hip = 2;
  static const shoulderBack = 3; // + elbow, + hand
  static const shoulderFront = 6;
  static const hipBack = 9; // + knee, + foot
  static const hipFront = 12;

  final List<Offset> points;

  /// Side view: the back arm and leg sit a little behind the front ones.
  factory _Pose.side({
    required Offset head,
    required Offset neck,
    required Offset hip,
    required Offset elbow,
    required Offset hand,
    required Offset knee,
    required Offset foot,
    Offset back = const Offset(-4, 0),
  }) =>
      _Pose([
        head, neck, hip, //
        neck + back, elbow + back, hand + back,
        neck, elbow, hand,
        hip + back, knee + back, foot + back,
        hip, knee, foot,
      ]);

  /// Front view: left side is "back", right side is "front".
  factory _Pose.front({
    required double headY,
    required double neckY,
    required double hipY,
    required Offset elbow,
    required Offset hand,
    required Offset knee,
    required Offset foot,
  }) {
    Offset m(Offset o) => Offset(100 - o.dx, o.dy);
    final shoulder = Offset(56, neckY + 2);
    final hipJoint = Offset(54, hipY + 2);
    return _Pose([
      Offset(50, headY), Offset(50, neckY), Offset(50, hipY), //
      m(shoulder), m(elbow), m(hand),
      shoulder, elbow, hand,
      m(hipJoint), m(knee), m(foot),
      hipJoint, knee, foot,
    ]);
  }

  static _Pose lerp(_Pose a, _Pose b, double t) =>
      _Pose(List<Offset>.generate(a.points.length, (i) => Offset.lerp(a.points[i], b.points[i], t)!));
}

/// Two key poses per move (A → B → A is one rep).
final Map<ExerciseMove, (_Pose, _Pose)> _keyframes = {
  // Push-up: straight arms (high plank) → elbows bent, body low.
  ExerciseMove.pushup: (
    _Pose.side(
      head: const Offset(76.6, 46.9),
      neck: const Offset(68, 52),
      hip: const Offset(40, 68.6),
      elbow: const Offset(68, 69),
      hand: const Offset(68, 86),
      knee: const Offset(27, 76.3),
      foot: const Offset(14, 84),
    ),
    _Pose.side(
      head: const Offset(79.5, 62.9),
      neck: const Offset(70, 66),
      hip: const Offset(40, 75.6),
      elbow: const Offset(60, 74),
      hand: const Offset(68, 86),
      knee: const Offset(27, 79.8),
      foot: const Offset(14, 84),
    ),
  ),
  // Sit-up: lying on the back, knees bent → curled up, hands past the knees.
  ExerciseMove.situp: (
    _Pose.side(
      head: const Offset(10, 78),
      neck: const Offset(19, 79),
      hip: const Offset(42, 80),
      elbow: const Offset(31, 78),
      hand: const Offset(42, 74),
      knee: const Offset(58, 64),
      foot: const Offset(72, 84),
    ),
    _Pose.side(
      head: const Offset(53.4, 48.6),
      neck: const Offset(50, 58),
      hip: const Offset(42, 80),
      elbow: const Offset(61, 57),
      hand: const Offset(72, 58),
      knee: const Offset(58, 64),
      foot: const Offset(72, 84),
    ),
  ),
  // Jumping jack (front view): arms down, feet together → arms up in a V,
  // feet apart, a small hop.
  ExerciseMove.jacks: (
    _Pose.front(
      headY: 19,
      neckY: 30,
      hipY: 56,
      elbow: const Offset(59, 44),
      hand: const Offset(60, 56),
      knee: const Offset(55, 72),
      foot: const Offset(55, 86),
    ),
    _Pose.front(
      headY: 16,
      neckY: 27,
      hipY: 53,
      elbow: const Offset(66, 18),
      hand: const Offset(71, 7),
      knee: const Offset(62, 69),
      foot: const Offset(68, 84),
    ),
  ),
  // Squat: standing, arms forward → hips back and down, knees bent.
  ExerciseMove.squat: (
    _Pose.side(
      head: const Offset(47, 17),
      neck: const Offset(47, 27),
      hip: const Offset(46, 55),
      elbow: const Offset(57, 30),
      hand: const Offset(67, 30),
      knee: const Offset(48, 70),
      foot: const Offset(47, 86),
    ),
    _Pose.side(
      head: const Offset(52.6, 38.1),
      neck: const Offset(48, 47),
      hip: const Offset(36, 70),
      elbow: const Offset(59, 48),
      hand: const Offset(70, 48),
      knee: const Offset(54, 70),
      foot: const Offset(47, 86),
    ),
  ),
  // Toe touch: standing tall, arms up → bend forward, hands to the toes.
  ExerciseMove.toes: (
    _Pose.side(
      head: const Offset(46, 17),
      neck: const Offset(46, 27),
      hip: const Offset(46, 54),
      elbow: const Offset(57, 21),
      hand: const Offset(63, 11),
      knee: const Offset(46, 70),
      foot: const Offset(46, 86),
    ),
    _Pose.side(
      head: const Offset(75, 70.5),
      neck: const Offset(66, 66),
      hip: const Offset(42, 54),
      elbow: const Offset(60, 76),
      hand: const Offset(54, 84),
      knee: const Offset(44, 70),
      foot: const Offset(46, 86),
    ),
  ),
  // Generic stretch (front view): arms down → arms out to the sides.
  ExerciseMove.generic: (
    _Pose.front(
      headY: 19,
      neckY: 30,
      hipY: 56,
      elbow: const Offset(59, 44),
      hand: const Offset(60, 56),
      knee: const Offset(56, 72),
      foot: const Offset(57, 86),
    ),
    _Pose.front(
      headY: 18,
      neckY: 29,
      hipY: 55,
      elbow: const Offset(66, 31),
      hand: const Offset(77, 29),
      knee: const Offset(56, 71),
      foot: const Offset(57, 86),
    ),
  ),
};
