import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Home: a friendly sunrise sky over a little town.
/// * Zad X Play: the town has a mosque (dome, minaret, crescents).
/// * Zad X Kids: the same spot holds a big oak with a treehouse, a rope ladder and a tyre swing
///   ([withMosque] false). No religious motif, no lettering.
class HomeStaticPainter extends CustomPainter {
  const HomeStaticPainter({this.withMosque = artReligiousMotifs});

  /// Draw the mosque (dome, minaret, crescents). Never in Zad X Kids.
  final bool withMosque;

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
      // Leave room for the mosque (Play) or the treehouse oak (Kids).
      if ((x + hw / 2 - mosqueX).abs() > (withMosque ? 60 : 56) * u) {
        final body = Rect.fromLTWH(x, ground - hh, hw, hh + 20 * u);
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(8 * u)), fill(houses[i % houses.length]));
        final win = Rect.fromLTWH(x + hw * 0.32, ground - hh + 12 * u, hw * 0.36, 14 * u);
        canvas.drawRRect(ArtShapes.arch(win), fill(ArtColors.windowGold));
      }
      x += hw + 8 * u;
      i++;
    }

    if (!withMosque) {
      _treehouse(canvas, Offset(mosqueX, ground), u);
      return;
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

  /// Zad X Kids focal point: a big round oak holding a little treehouse, a rope ladder and a
  /// tyre swing. Same footprint and palette as the mosque, so contrast and balance are unchanged.
  void _treehouse(Canvas canvas, Offset base, double u) {
    final cx = base.dx;
    final ground = base.dy;
    // Trunk with two branches.
    final trunk = Path()
      ..moveTo(cx - 13 * u, ground + 20 * u)
      ..cubicTo(cx - 10 * u, ground - 30 * u, cx - 9 * u, ground - 60 * u, cx - 7 * u, ground - 92 * u)
      ..lineTo(cx + 7 * u, ground - 92 * u)
      ..cubicTo(cx + 9 * u, ground - 60 * u, cx + 10 * u, ground - 30 * u, cx + 13 * u, ground + 20 * u)
      ..close();
    canvas.drawPath(trunk, fill(ArtColors.peach));
    final branch = Paint()
      ..color = ArtColors.peach
      ..strokeWidth = 7 * u
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - 4 * u, ground - 58 * u), Offset(cx - 38 * u, ground - 82 * u), branch);
    canvas.drawLine(Offset(cx + 4 * u, ground - 66 * u), Offset(cx + 40 * u, ground - 88 * u), branch);

    // Leafy crown: overlapping soft circles.
    for (final (dx, dy, r) in const [
      (-40.0, -104.0, 30.0), (40.0, -106.0, 30.0), (-18.0, -128.0, 34.0), (22.0, -130.0, 32.0), (0.0, -104.0, 34.0),
    ]) {
      canvas.drawCircle(Offset(cx + dx * u, ground + dy * u), r * u, fill(ArtColors.leaf));
    }
    canvas.drawCircle(Offset(cx - 30 * u, ground - 136 * u), 12 * u, fill(ArtColors.hillNear));
    canvas.drawCircle(Offset(cx + 34 * u, ground - 124 * u), 9 * u, fill(ArtColors.hillNear));

    // The treehouse on its platform.
    final deck = RRect.fromRectAndRadius(Rect.fromLTWH(cx - 34 * u, ground - 86 * u, 68 * u, 7 * u), Radius.circular(3 * u));
    canvas.drawRRect(deck, fill(ArtColors.lavender));
    final house = Rect.fromLTWH(cx - 24 * u, ground - 120 * u, 48 * u, 34 * u);
    canvas.drawRRect(RRect.fromRectAndRadius(house, Radius.circular(5 * u)), fill(ArtColors.iceBlue));
    final roof = Path()
      ..moveTo(house.left - 8 * u, house.top + 2 * u)
      ..lineTo(cx, house.top - 22 * u)
      ..lineTo(house.right + 8 * u, house.top + 2 * u)
      ..close();
    canvas.drawPath(roof, fill(ArtColors.gold));
    // Round window and a little door.
    canvas.drawCircle(Offset(cx - 9 * u, house.top + 14 * u), 6 * u, fill(ArtColors.windowGold));
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(cx + 5 * u, house.top + 10 * u, 12 * u, 24 * u), Radius.circular(4 * u)),
      fill(ArtColors.lilac),
    );
    // Tiny pennant on the roof (plain triangle flag, no symbol).
    final pole = Paint()
      ..color = ArtColors.peach
      ..strokeWidth = 2 * u
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx, house.top - 22 * u), Offset(cx, house.top - 40 * u), pole);
    canvas.drawPath(
      Path()
        ..moveTo(cx, house.top - 40 * u)
        ..lineTo(cx + 15 * u, house.top - 35 * u)
        ..lineTo(cx, house.top - 30 * u)
        ..close(),
      fill(ArtColors.sunGold),
    );

    // Rope ladder down the trunk side.
    final rope = Paint()
      ..color = ArtColors.lavender
      ..strokeWidth = 2 * u
      ..strokeCap = StrokeCap.round;
    final lx = cx - 30 * u;
    canvas.drawLine(Offset(lx, ground - 80 * u), Offset(lx, ground + 4 * u), rope);
    canvas.drawLine(Offset(lx + 12 * u, ground - 80 * u), Offset(lx + 12 * u, ground + 4 * u), rope);
    for (var y = ground - 70 * u; y < ground + 4 * u; y += 12 * u) {
      canvas.drawLine(Offset(lx, y), Offset(lx + 12 * u, y), rope);
    }

    // Tyre swing from the right branch.
    final sx = cx + 34 * u;
    canvas.drawLine(Offset(sx, ground - 84 * u), Offset(sx, ground - 22 * u), rope);
    canvas.drawCircle(
      Offset(sx, ground - 12 * u),
      10 * u,
      Paint()
        ..color = ArtColors.lavender
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * u,
    );
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
  bool shouldRepaint(HomeStaticPainter oldDelegate) => oldDelegate.withMosque != withMosque;
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
