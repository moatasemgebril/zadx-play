import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Home: a friendly sunrise sky over a little town with a mosque.
class HomeStaticPainter extends CustomPainter {
  const HomeStaticPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final u = sceneUnit(size);
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      vGradient(rect, const [ArtColors.homeSkyTop, ArtColors.homeSkyMid, ArtColors.homeSkyLow], const [0, 0.55, 1]),
    );

    // Rising sun behind the town (end side; mirrored automatically in RTL).
    final horizon = h - 150 * u;
    final sun = Offset(w * 0.76, horizon + 6 * u);
    canvas.drawCircle(sun, 120 * u, glow(sun, 120 * u, ArtColors.sunGold, 0.55));
    canvas.drawCircle(sun, 38 * u, fill(ArtColors.sunGold));

    // Far hills, then the town, then the near hill.
    canvas.drawPath(ArtShapes.hill(size, horizon, amp: 10 * u, waves: 1.2), fill(ArtColors.hillFar));
    _town(canvas, size, horizon + 14 * u, u);
    canvas.drawPath(ArtShapes.hill(size, h - 46 * u, amp: 8 * u, waves: 0.8, phase: 0.3), fill(ArtColors.hillNear));
    _trees(canvas, size, h - 52 * u, u);
  }

  void _town(Canvas canvas, Size size, double ground, double u) {
    const houses = [ArtColors.peach, ArtColors.lilac, ArtColors.iceBlue];
    const heights = [46.0, 62.0, 40.0, 54.0, 70.0, 44.0];
    final mosqueX = size.width * 0.3;
    var x = -10 * u;
    var i = 0;
    while (x < size.width) {
      final hw = (34 + (i % 3) * 6) * u;
      final hh = heights[i % heights.length] * u;
      // Leave room for the mosque.
      if ((x + hw / 2 - mosqueX).abs() > 60 * u) {
        final body = Rect.fromLTWH(x, ground - hh, hw, hh + 20 * u);
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(8 * u)), fill(houses[i % houses.length]));
        final win = Rect.fromLTWH(x + hw * 0.32, ground - hh + 12 * u, hw * 0.36, 14 * u);
        canvas.drawRRect(ArtShapes.arch(win), fill(ArtColors.windowGold));
      }
      x += hw + 8 * u;
      i++;
    }

    // Mosque: main hall, dome, one minaret, crescents. Architecture only.
    final hallW = 92 * u;
    final hall = Rect.fromLTWH(mosqueX - hallW / 2, ground - 48 * u, hallW, 68 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(hall, Radius.circular(6 * u)), fill(ArtColors.lavender));
    final domeW = 60 * u;
    canvas.drawPath(ArtShapes.dome(Offset(mosqueX - domeW / 2, hall.top + 2 * u), domeW, hall.top - 52 * u), fill(ArtColors.lavender));
    canvas.drawPath(ArtShapes.crescent(Offset(mosqueX, hall.top - 62 * u), 7 * u), fill(ArtColors.gold));
    final door = Rect.fromLTWH(mosqueX - 12 * u, ground - 26 * u, 24 * u, 40 * u);
    canvas.drawRRect(ArtShapes.arch(door), fill(ArtColors.windowGold));
    for (final dx in [-32.0, 32.0]) {
      final win = Rect.fromLTWH(mosqueX + dx * u - 6 * u, ground - 34 * u, 12 * u, 18 * u);
      canvas.drawRRect(ArtShapes.arch(win), fill(ArtColors.windowGold));
    }
    final minX = hall.right + 6 * u;
    final minaret = Rect.fromLTWH(minX, ground - 120 * u, 16 * u, 140 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(minaret, Radius.circular(4 * u)), fill(ArtColors.lavender));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(minX - 4 * u, ground - 92 * u, 24 * u, 6 * u), Radius.circular(3 * u)),
      fill(ArtColors.lilac),
    );
    canvas.drawPath(ArtShapes.dome(Offset(minX, minaret.top + 1), 16 * u, minaret.top - 18 * u), fill(ArtColors.lavender));
    canvas.drawPath(ArtShapes.crescent(Offset(minX + 8 * u, minaret.top - 24 * u), 4.5 * u), fill(ArtColors.gold));
  }

  void _trees(Canvas canvas, Size size, double y, double u) {
    for (final f in [0.08, 0.55, 0.93]) {
      final c = Offset(size.width * f, y);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c + Offset(0, 14 * u), width: 6 * u, height: 22 * u), Radius.circular(3 * u)),
        fill(ArtColors.peach),
      );
      canvas.drawCircle(c, 16 * u, fill(ArtColors.leaf));
    }
  }

  @override
  bool shouldRepaint(HomeStaticPainter oldDelegate) => false;
}

/// Home motion: slow drifting clouds and a softly breathing sun glow.
class HomeMotionPainter extends CustomPainter {
  HomeMotionPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final u = sceneUnit(size);
    final v = t.value;
    final h = size.height;
    final sun = Offset(size.width * 0.76, h - 144 * u);
    final pulse = 1 + 0.06 * Loop.wave(v, 4);
    canvas.drawCircle(sun, 60 * u * pulse, glow(sun, 60 * u * pulse, ArtColors.white, 0.35));

    const clouds = [(0.10, 120.0, 0.0), (0.24, 90.0, 0.45), (0.40, 140.0, 0.75)];
    for (final (yf, cw, start) in clouds) {
      final w = cw * u;
      final x = Loop.drift(v, 1, start) * (size.width + 2 * w) - w;
      canvas.drawPath(ArtShapes.cloud(Offset(x, h * yf + 40 * u), w), fill(ArtColors.white, 0.85));
    }
  }

  @override
  bool shouldRepaint(HomeMotionPainter oldDelegate) => oldDelegate.t != t;
}
