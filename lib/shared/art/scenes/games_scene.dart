import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Games: playful floating islands in a candy-pastel sky.
class GamesStaticPainter extends CustomPainter {
  const GamesStaticPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      vGradient(rect, const [ArtColors.gamesSkyTop, ArtColors.gamesSkyMid, ArtColors.gamesSkyLow], const [0, 0.5, 1]),
    );
    final u = sceneUnit(size);
    // Far, still clouds for depth.
    for (final (xf, yf, cw) in const [(0.2, 0.16, 110.0), (0.82, 0.5, 130.0), (0.12, 0.86, 120.0)]) {
      canvas.drawPath(ArtShapes.cloud(Offset(size.width * xf, size.height * yf), cw * u), fill(ArtColors.white, 0.7));
    }
  }

  @override
  bool shouldRepaint(GamesStaticPainter oldDelegate) => false;
}

/// Games motion: islands bob gently, balloons float, sparkles twinkle softly.
class GamesMotionPainter extends CustomPainter {
  GamesMotionPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  // (x, y, width, phase, grass/earth variant)
  static const _islands = [
    (0.20, 0.20, 96.0, 0.0, 0),
    (0.80, 0.36, 118.0, 0.3, 1),
    (0.28, 0.58, 124.0, 0.6, 0),
    (0.78, 0.78, 104.0, 0.15, 1),
    (0.48, 0.95, 150.0, 0.8, 0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final u = sceneUnit(size);
    final v = t.value;
    for (var i = 0; i < _islands.length; i++) {
      final (xf, yf, iw, ph, variant) = _islands[i];
      final bob = 6 * u * Loop.wave(v, 2, ph);
      _island(canvas, Offset(size.width * xf, size.height * yf + bob), iw * u, variant, i);
    }

    // Two balloons rising slowly and wrapping round.
    const balloons = [(0.62, 0.0, ArtColors.balloonCoral), (0.10, 0.5, ArtColors.balloonLilac)];
    for (final (xf, start, color) in balloons) {
      final y = (1 - Loop.drift(v, 1, start)) * (size.height + 120 * u) - 40 * u;
      final x = size.width * xf + 8 * u * Loop.wave(v, 3, start);
      _balloon(canvas, Offset(x, y), u, color);
    }

    // Soft gold sparkles (slow, low-contrast twinkle: never a flash).
    const sparkles = [(0.12, 0.07), (0.9, 0.14), (0.55, 0.27), (0.06, 0.45), (0.94, 0.62), (0.6, 0.7)];
    for (var i = 0; i < sparkles.length; i++) {
      final (xf, yf) = sparkles[i];
      final a = 0.55 + 0.35 * Loop.wave(v, 3, i / sparkles.length);
      canvas.drawPath(ArtShapes.sparkle(Offset(size.width * xf, size.height * yf), 7 * u), fill(ArtColors.gold, a));
    }
  }

  void _island(Canvas canvas, Offset c, double w, int variant, int i) {
    final h = w * 0.55;
    final earth = Path()
      ..moveTo(c.dx - w / 2, c.dy)
      ..quadraticBezierTo(c.dx - w * 0.3, c.dy + h * 0.5, c.dx, c.dy + h)
      ..quadraticBezierTo(c.dx + w * 0.3, c.dy + h * 0.5, c.dx + w / 2, c.dy)
      ..close();
    canvas.drawPath(earth, fill(variant == 0 ? ArtColors.islandEarth : ArtColors.islandPink));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: w * 1.04, height: w * 0.16), Radius.circular(w * 0.08)),
      fill(ArtColors.islandGrass),
    );
    // A round tree or a gold star on top, alternating.
    if (i.isEven) {
      final tc = c + Offset(-w * 0.18, -w * 0.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: tc + Offset(0, w * 0.1), width: w * 0.05, height: w * 0.16), Radius.circular(w * 0.03)),
        fill(ArtColors.islandEarth),
      );
      canvas.drawCircle(tc, w * 0.13, fill(ArtColors.leaf));
    } else {
      canvas.drawPath(ArtShapes.star(c + Offset(w * 0.16, -w * 0.18), w * 0.12), fill(ArtColors.softGold));
    }
  }

  void _balloon(Canvas canvas, Offset c, double u, Color color) {
    final string = Paint()
      ..color = ArtColors.white
      ..strokeWidth = 1.5 * u
      ..style = PaintingStyle.stroke;
    canvas.drawLine(c + Offset(0, 20 * u), c + Offset(2 * u, 48 * u), string);
    canvas.drawOval(Rect.fromCenter(center: c, width: 30 * u, height: 38 * u), fill(color));
    canvas.drawOval(Rect.fromCenter(center: c + Offset(-6 * u, -8 * u), width: 7 * u, height: 10 * u), fill(ArtColors.white, 0.7));
  }

  @override
  bool shouldRepaint(GamesMotionPainter oldDelegate) => oldDelegate.t != t;
}
