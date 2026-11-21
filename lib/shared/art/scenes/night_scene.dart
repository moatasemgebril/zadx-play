import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Quran & Adhkar: a calm night sky, crescent, stars, hanging lanterns and a
/// faint geometric pattern. Calmer than any game screen: motion is minimal
/// (slow twinkle, a barely-there lantern sway) and nothing is playful.
class NightStaticPainter extends CustomPainter {
  const NightStaticPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final u = sceneUnit(size);
    canvas.drawRect(
      rect,
      vGradient(rect, const [ArtColors.nightTop, ArtColors.nightMid, ArtColors.nightLow], const [0, 0.6, 1]),
    );

    // Faint eight-point-star lattice.
    final line = Paint()
      ..color = ArtColors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * u;
    final step = 72 * u;
    for (var y = step / 2; y < size.height + step; y += step) {
      final odd = ((y / step).floor()).isOdd;
      for (var x = odd ? step : step / 2; x < size.width + step; x += step) {
        canvas.drawPath(ArtShapes.eightPointStar(Offset(x, y), step * 0.32), line);
      }
    }

    // Crescent with a soft halo (top end side).
    final moon = Offset(size.width * 0.82, 96 * u);
    canvas.drawCircle(moon, 70 * u, glow(moon, 70 * u, ArtColors.moonGlow, 0.22));
    canvas.drawPath(ArtShapes.crescent(moon, 26 * u), fill(ArtColors.moonGlow));

    // Tiny fixed stars.
    final r = math.Random(30);
    for (var i = 0; i < 40; i++) {
      final p = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height * 0.85);
      canvas.drawCircle(p, (0.8 + r.nextDouble()) * u, fill(ArtColors.white, 0.35));
    }

    // Quiet skyline of domes and a minaret at the bottom.
    final ground = size.height - 40 * u;
    final sky = Paint()..color = ArtColors.nightSkyline.withValues(alpha: 0.8);
    canvas.drawRect(Rect.fromLTRB(0, ground, size.width, size.height), sky);
    for (final (xf, dw) in const [(0.18, 70.0), (0.5, 96.0), (0.82, 64.0)]) {
      final w = dw * u;
      final cx = size.width * xf;
      canvas.drawRect(Rect.fromLTWH(cx - w / 2, ground - w * 0.35, w, w * 0.36), sky);
      canvas.drawPath(ArtShapes.dome(Offset(cx - w * 0.38, ground - w * 0.34), w * 0.76, ground - w * 1.05), sky);
    }
    final mx = size.width * 0.66;
    canvas.drawRect(Rect.fromLTWH(mx, ground - 120 * u, 12 * u, 120 * u), sky);
    canvas.drawPath(ArtShapes.dome(Offset(mx, ground - 119 * u), 12 * u, ground - 136 * u), sky);
  }

  @override
  bool shouldRepaint(NightStaticPainter oldDelegate) => false;
}

class NightMotionPainter extends CustomPainter {
  NightMotionPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  static const _lanterns = [(0.12, 46.0, 0.0), (0.34, 84.0, 0.33), (0.58, 60.0, 0.66)];

  @override
  void paint(Canvas canvas, Size size) {
    final u = sceneUnit(size);
    final v = t.value;

    // Slow twinkle: each star takes 12–24 s per cycle, alpha 0.3–0.85.
    final r = math.Random(11);
    for (var i = 0; i < 16; i++) {
      final p = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height * 0.7);
      final a = 0.575 + 0.275 * Loop.wave(v, 2 + i % 3, r.nextDouble());
      canvas.drawPath(ArtShapes.sparkle(p, (4 + (i % 3) * 1.5) * u), fill(ArtColors.white, a));
    }

    // Hanging lanterns, swaying less than 2 degrees.
    for (final (xf, len, ph) in _lanterns) {
      final top = Offset(size.width * xf, 0);
      canvas.save();
      canvas.translate(top.dx, top.dy);
      canvas.rotate(0.03 * Loop.wave(v, 3, ph));
      _lantern(canvas, len * u, u);
      canvas.restore();
    }
  }

  void _lantern(Canvas canvas, double len, double u) {
    final cord = Paint()
      ..color = ArtColors.moonGlow.withValues(alpha: 0.6)
      ..strokeWidth = 1.4 * u;
    canvas.drawLine(Offset.zero, Offset(0, len), cord);
    final c = Offset(0, len + 22 * u);
    canvas.drawCircle(c, 46 * u, glow(c, 46 * u, ArtColors.gold, 0.28));
    // Cap.
    canvas.drawPath(
      Path()
        ..moveTo(-9 * u, len + 6 * u)
        ..lineTo(0, len - 2 * u)
        ..lineTo(9 * u, len + 6 * u)
        ..close(),
      fill(ArtColors.gold),
    );
    // Body: a rounded hexagon with a warm window.
    final body = Path()
      ..moveTo(-8 * u, len + 6 * u)
      ..lineTo(8 * u, len + 6 * u)
      ..lineTo(13 * u, len + 22 * u)
      ..lineTo(8 * u, len + 38 * u)
      ..lineTo(-8 * u, len + 38 * u)
      ..lineTo(-13 * u, len + 22 * u)
      ..close();
    canvas.drawPath(body, fill(ArtColors.gold));
    canvas.drawRRect(ArtShapes.arch(Rect.fromCenter(center: c, width: 10 * u, height: 20 * u)), fill(ArtColors.moonGlow));
    canvas.drawCircle(Offset(0, len + 42 * u), 3 * u, fill(ArtColors.gold));
  }

  @override
  bool shouldRepaint(NightMotionPainter oldDelegate) => oldDelegate.t != t;
}
