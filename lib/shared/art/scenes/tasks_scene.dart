import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Number of flower spots in the garden.
const gardenSlots = 9;

/// How many flowers are in bloom for today's task [progress] (0..1).
/// Any progress above zero shows at least one flower, so the first task
/// done is always rewarded visibly.
int gardenBloomCount(double progress, {int slots = gardenSlots}) {
  if (progress.isNaN || progress <= 0) return 0;
  final n = (progress.clamp(0.0, 1.0) * slots).round();
  return n < 1 ? 1 : n;
}

/// Tasks: a garden that grows as today's tasks are done.
class TasksStaticPainter extends CustomPainter {
  const TasksStaticPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final u = sceneUnit(size);
    canvas.drawRect(rect, vGradient(rect, const [ArtColors.gardenSkyTop, ArtColors.gardenSkyLow]));
    final sun = Offset(size.width * 0.86, 70 * u);
    canvas.drawCircle(sun, 90 * u, glow(sun, 90 * u, ArtColors.sunGold, 0.5));
    canvas.drawCircle(sun, 30 * u, fill(ArtColors.sunGold));
    canvas.drawPath(ArtShapes.hill(size, size.height - 130 * u, amp: 12 * u, waves: 1.1), fill(ArtColors.gardenBack));
    canvas.drawPath(ArtShapes.hill(size, size.height - 70 * u, amp: 8 * u, waves: 0.7, phase: 0.4), fill(ArtColors.gardenFront));
  }

  @override
  bool shouldRepaint(TasksStaticPainter oldDelegate) => false;
}

/// Tasks motion: flowers (bloomed = tasks done) sway; a butterfly visits
/// once at least one task is done.
class TasksMotionPainter extends CustomPainter {
  TasksMotionPainter(this.t, {required this.blooms}) : super(repaint: t);
  final Animation<double> t;
  final int blooms;

  static const _petals = [ArtColors.balloonCoral, ArtColors.softGold, ArtColors.balloonLilac, ArtColors.balloonSky];
  // Order in which spots bloom, so flowers spread across the garden.
  static const _order = [4, 1, 7, 2, 6, 0, 8, 3, 5];

  @override
  void paint(Canvas canvas, Size size) {
    final u = sceneUnit(size);
    final v = t.value;
    final ground = size.height - 64 * u;
    final bloomed = {for (var i = 0; i < blooms && i < _order.length; i++) _order[i]};
    for (var s = 0; s < gardenSlots; s++) {
      final x = size.width * (0.06 + 0.88 * s / (gardenSlots - 1));
      final base = Offset(x, ground + (s.isEven ? 10 : 0) * u);
      final height = (44 + (s * 7) % 26) * u;
      final sway = 4 * u * Loop.wave(v, 2, s * 0.11);
      final top = base + Offset(sway, -height);
      final stem = Paint()
        ..color = ArtColors.stem
        ..strokeWidth = 4 * u
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      if (bloomed.contains(s)) {
        canvas.drawPath(Path()..moveTo(base.dx, base.dy)..quadraticBezierTo(base.dx, base.dy - height * 0.5, top.dx, top.dy), stem);
        canvas.drawOval(Rect.fromCenter(center: base + Offset(6 * u, -height * 0.4), width: 14 * u, height: 7 * u), fill(ArtColors.stem));
        final color = _petals[s % _petals.length];
        for (var p = 0; p < 5; p++) {
          final a = p * 2 * math.pi / 5;
          canvas.drawCircle(top + Offset(math.cos(a), math.sin(a)) * 9 * u, 7.5 * u, fill(color));
        }
        canvas.drawCircle(top, 6 * u, fill(ArtColors.flowerCentre));
      } else {
        // A little sprout waiting for the next task.
        final sproutTop = base + Offset(sway * 0.4, -16 * u);
        canvas.drawLine(base, sproutTop, stem);
        canvas.drawOval(Rect.fromCenter(center: sproutTop + Offset(-5 * u, 0), width: 10 * u, height: 6 * u), fill(ArtColors.stem));
        canvas.drawOval(Rect.fromCenter(center: sproutTop + Offset(5 * u, -2 * u), width: 10 * u, height: 6 * u), fill(ArtColors.stem));
      }
    }

    if (blooms > 0) {
      final bx = Loop.drift(v, 1, 0.2) * (size.width + 60 * u) - 30 * u;
      final by = ground - 120 * u + 18 * u * Loop.wave(v, 3);
      final flap = 0.55 + 0.45 * Loop.wave(v, 16).abs();
      final c = Offset(bx, by);
      for (final side in const [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(center: c + Offset(side * 6 * u * flap, -3 * u), width: 11 * u * flap, height: 13 * u),
          fill(ArtColors.balloonLilac),
        );
        canvas.drawOval(
          Rect.fromCenter(center: c + Offset(side * 5 * u * flap, 5 * u), width: 8 * u * flap, height: 8 * u),
          fill(ArtColors.balloonCoral),
        );
      }
      canvas.drawOval(Rect.fromCenter(center: c, width: 3 * u, height: 14 * u), fill(ArtColors.stem));
    }
  }

  @override
  bool shouldRepaint(TasksMotionPainter oldDelegate) => oldDelegate.t != t || oldDelegate.blooms != blooms;
}
