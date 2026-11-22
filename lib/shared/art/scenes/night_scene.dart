import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Quran & Adhkar: a calm night sky, crescent, stars, hanging lanterns and a
/// faint geometric pattern. Calmer than any game screen: motion is minimal
/// (slow twinkle, a barely-there lantern sway) and nothing is playful.
///
/// Zad X Kids ([religiousMotifs] false) never shows the Quran area; if a night scene is ever
/// shown there it is a neutral "space" sky instead: full moon with craters, a ringed planet,
/// stars, rolling hills with pine trees and cosy houses, and a little rocket drifting by
/// (no crescent, no lanterns, no domes, no geometric star lattice).
class NightStaticPainter extends CustomPainter {
  const NightStaticPainter({this.religiousMotifs = artReligiousMotifs});

  final bool religiousMotifs;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final u = sceneUnit(size);
    canvas.drawRect(
      rect,
      vGradient(rect, const [ArtColors.nightTop, ArtColors.nightMid, ArtColors.nightLow], const [0, 0.6, 1]),
    );
    if (!religiousMotifs) {
      _space(canvas, size, u);
      return;
    }

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

  /// Zad X Kids: neutral space sky.
  void _space(Canvas canvas, Size size, double u) {
    // Tiny fixed stars.
    final r = math.Random(30);
    for (var i = 0; i < 46; i++) {
      final p = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height * 0.85);
      canvas.drawCircle(p, (0.8 + r.nextDouble()) * u, fill(ArtColors.white, 0.35));
    }
    // Full moon with soft craters (round, never a crescent).
    final moon = Offset(size.width * 0.8, 100 * u);
    canvas.drawCircle(moon, 74 * u, glow(moon, 74 * u, ArtColors.moonGlow, 0.22));
    canvas.drawCircle(moon, 26 * u, fill(ArtColors.moonGlow));
    for (final (dx, dy, cr) in const [(-8.0, -6.0, 6.0), (9.0, 5.0, 4.5), (-3.0, 12.0, 3.2), (10.0, -11.0, 2.6)]) {
      canvas.drawCircle(moon + Offset(dx * u, dy * u), cr * u, fill(ArtColors.sunGold, 0.55));
    }
    // A ringed planet on the start side.
    final planet = Offset(size.width * 0.16, size.height * 0.3);
    final ring = Paint()
      ..color = ArtColors.balloonSky.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * u;
    final ringRect = Rect.fromCenter(center: planet, width: 64 * u, height: 18 * u);
    canvas.drawArc(ringRect, math.pi, math.pi, false, ring); // back half
    canvas.drawCircle(planet, 17 * u, fill(ArtColors.balloonLilac));
    canvas.drawCircle(planet + Offset(-5 * u, -5 * u), 5 * u, fill(ArtColors.white, 0.35));
    canvas.drawArc(ringRect, 0, math.pi, false, ring); // front half

    // Rolling hills with pine trees and two cosy houses.
    final hills = Paint()..color = ArtColors.nightSkyline.withValues(alpha: 0.85);
    canvas.drawPath(ArtShapes.hill(size, size.height - 52 * u, amp: 12 * u, waves: 1.1), hills);
    final ground = size.height - 40 * u;
    for (final (xf, th) in const [(0.1, 44.0), (0.3, 58.0), (0.72, 50.0), (0.9, 40.0)]) {
      final cx = size.width * xf;
      final h = th * u;
      canvas.drawPath(
        Path()
          ..moveTo(cx - h * 0.32, ground - 4 * u)
          ..lineTo(cx, ground - h)
          ..lineTo(cx + h * 0.32, ground - 4 * u)
          ..close(),
        hills,
      );
    }
    for (final xf in const [0.48, 0.58]) {
      final cx = size.width * xf;
      final body = Rect.fromLTWH(cx - 15 * u, ground - 26 * u, 30 * u, 30 * u);
      canvas.drawRect(body, hills);
      canvas.drawPath(
        Path()
          ..moveTo(body.left - 5 * u, body.top + 1)
          ..lineTo(cx, body.top - 16 * u)
          ..lineTo(body.right + 5 * u, body.top + 1)
          ..close(),
        hills,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx - 5 * u, body.top + 8 * u, 10 * u, 9 * u), Radius.circular(2 * u)),
        fill(ArtColors.windowGold, 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(NightStaticPainter oldDelegate) => oldDelegate.religiousMotifs != religiousMotifs;
}

class NightMotionPainter extends CustomPainter {
  NightMotionPainter(this.t, {this.religiousMotifs = artReligiousMotifs}) : super(repaint: t);
  final Animation<double> t;

  /// False in Zad X Kids: a drifting rocket replaces the hanging lanterns.
  final bool religiousMotifs;

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

    if (!religiousMotifs) {
      _rocket(canvas, size, u, v);
      return;
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

  /// Zad X Kids: a small rocket drifting slowly across the sky once per loop, bobbing gently.
  void _rocket(Canvas canvas, Size size, double u, double v) {
    final x = Loop.drift(v, 1, 0.3) * (size.width + 120 * u) - 60 * u;
    final y = size.height * 0.5 + 14 * u * Loop.wave(v, 3);
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(math.pi / 2 - 0.35); // nose pointing ahead and slightly up
    // Soft exhaust glow (steady alpha: no flicker).
    canvas.drawCircle(Offset(0, 24 * u), 14 * u, glow(Offset(0, 24 * u), 14 * u, ArtColors.gold, 0.5));
    for (final side in const [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(side * 6 * u, 4 * u)
          ..lineTo(side * 14 * u, 18 * u)
          ..lineTo(side * 6 * u, 16 * u)
          ..close(),
        fill(ArtColors.balloonCoral),
      );
    }
    final body = Path()
      ..moveTo(0, -22 * u)
      ..cubicTo(10 * u, -12 * u, 10 * u, 8 * u, 7 * u, 16 * u)
      ..lineTo(-7 * u, 16 * u)
      ..cubicTo(-10 * u, 8 * u, -10 * u, -12 * u, 0, -22 * u)
      ..close();
    canvas.drawPath(body, fill(ArtColors.white));
    canvas.drawCircle(Offset(0, -4 * u), 4 * u, fill(ArtColors.balloonSky));
    canvas.restore();
  }

  @override
  bool shouldRepaint(NightMotionPainter oldDelegate) => oldDelegate.t != t || oldDelegate.religiousMotifs != religiousMotifs;
}
