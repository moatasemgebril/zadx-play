import 'dart:math' as math;
import 'dart:ui';

import '../../core/app_variant.dart';

/// True when this build may draw religious motifs (mosque, dome, minaret, crescent, lantern,
/// eight-point Islamic star). Compile-time constant: false in Zad X Kids, so every Kids painter
/// takes its neutral branch (treehouse, full moon, planets, dot grid) and the religious drawing
/// code is tree-shaken. docs/decisions/ZADX-KIDS-VARIANT.md, "Artwork rules".
const bool artReligiousMotifs = !kIsKids;

/// Small, original shape helpers shared by the Zad X scenes, icons and
/// celebrations. Everything is drawn in code: no bitmaps, no third-party art.
///
/// Islamic rule for every caller: scenery, objects and architecture only.
/// Never draw a person, face, prophet, angel or companion, and never draw
/// music notes or instruments.
///
/// Zad X Kids rule: no religious motif and no Arabic script in any artwork. [crescent], [dome] and
/// [eightPointStar] assert [artReligiousMotifs], so a Kids test that paints them fails.
abstract final class ArtShapes {
  /// Debug/test only: how many religious motifs ([crescent], [dome], [eightPointStar]) were built
  /// since the last reset. Tests paint a Kids scene and expect 0.
  static int debugReligiousMotifCount = 0;

  /// Debug-mode guard of every religious motif: counts it, and fails in a Zad X Kids build.
  static bool _religiousMotif(String what) {
    debugReligiousMotifCount++;
    assert(artReligiousMotifs, '$what drawn in Zad X Kids (docs/decisions/ZADX-KIDS-VARIANT.md)');
    return true;
  }

  /// A star with [points] tips. [inner] is the inner radius as a fraction of [r].
  static Path star(Offset c, double r, {int points = 5, double inner = 0.48, double rotation = -math.pi / 2}) {
    final p = Path();
    for (var i = 0; i < points * 2; i++) {
      final rad = i.isEven ? r : r * inner;
      final a = rotation + i * math.pi / points;
      final x = c.dx + math.cos(a) * rad;
      final y = c.dy + math.sin(a) * rad;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    return p..close();
  }

  /// Four-point sparkle (used for twinkles and celebrations).
  static Path sparkle(Offset c, double r) => star(c, r, points: 4, inner: 0.32);

  /// Eight-point star made of two overlapping squares (a classic Islamic
  /// geometric motif), as a single outline.
  static Path eightPointStar(Offset c, double r) {
    assert(_religiousMotif('Islamic eight-point star'));
    final p = Path();
    final innerR = r * math.cos(math.pi / 4) / math.cos(math.pi / 8);
    for (var i = 0; i < 16; i++) {
      final rad = i.isEven ? r : innerR;
      final a = -math.pi / 2 + i * math.pi / 8;
      final x = c.dx + math.cos(a) * rad;
      final y = c.dy + math.sin(a) * rad;
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
    }
    return p..close();
  }

  /// Crescent moon centred on [c] with outer radius [r], opening to the right.
  /// Built analytically from two arcs (no path boolean ops, so it renders the
  /// same on every Flutter backend).
  static Path crescent(Offset c, double r, {double offset = 0.55, double innerScale = 0.9}) {
    assert(_religiousMotif('Crescent'));
    final dx = r * offset;
    final ri = r * innerScale;
    final x0 = (r * r - ri * ri + dx * dx) / (2 * dx);
    final y0 = math.sqrt(math.max(0, r * r - x0 * x0));
    final alpha = math.atan2(y0, x0);
    final phi = math.atan2(y0, x0 - dx);
    final outer = Rect.fromCircle(center: c, radius: r);
    final inner = Rect.fromCircle(center: c + Offset(dx, 0), radius: ri);
    return Path()
      ..moveTo(c.dx + x0, c.dy - y0)
      ..arcTo(outer, -alpha, -(2 * math.pi - 2 * alpha), false)
      ..arcTo(inner, phi, 2 * math.pi - 2 * phi, false)
      ..close();
  }

  /// A puffy cloud whose base is centred on [base], [w] wide.
  static Path cloud(Offset base, double w) {
    final h = w * 0.42;
    final p = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(base.dx - w / 2, base.dy - h * 0.55, w, h * 0.55),
        Radius.circular(h * 0.3),
      ))
      ..addOval(Rect.fromCircle(center: Offset(base.dx - w * 0.22, base.dy - h * 0.55), radius: h * 0.36))
      ..addOval(Rect.fromCircle(center: Offset(base.dx + w * 0.02, base.dy - h * 0.72), radius: h * 0.5))
      ..addOval(Rect.fromCircle(center: Offset(base.dx + w * 0.26, base.dy - h * 0.5), radius: h * 0.33));
    return p;
  }

  /// Onion dome sitting on [baseLeft]..[baseLeft + width], tip at [tipY].
  static Path dome(Offset baseLeft, double width, double tipY) {
    assert(_religiousMotif('Dome'));
    final x0 = baseLeft.dx;
    final y0 = baseLeft.dy;
    final x1 = x0 + width;
    final mid = x0 + width / 2;
    final h = y0 - tipY;
    return Path()
      ..moveTo(x0, y0)
      ..cubicTo(x0 - width * 0.08, y0 - h * 0.55, mid - width * 0.18, tipY + h * 0.28, mid, tipY)
      ..cubicTo(mid + width * 0.18, tipY + h * 0.28, x1 + width * 0.08, y0 - h * 0.55, x1, y0)
      ..close();
  }

  /// Rounded-top arch (doors and windows).
  static RRect arch(Rect r) => RRect.fromRectAndCorners(
        r,
        topLeft: Radius.circular(r.width / 2),
        topRight: Radius.circular(r.width / 2),
      );

  /// A gentle rolling hill filling from [y] to the bottom of [size].
  static Path hill(Size size, double y, {double amp = 18, double waves = 1.5, double phase = 0}) {
    final p = Path()..moveTo(0, size.height);
    const steps = 24;
    for (var i = 0; i <= steps; i++) {
      final x = size.width * i / steps;
      final yy = y - amp * math.sin((i / steps * waves + phase) * 2 * math.pi);
      p.lineTo(x, yy);
    }
    return p
      ..lineTo(size.width, size.height)
      ..close();
  }

  /// Heart centred on [c], [s] wide.
  static Path heart(Offset c, double s) {
    final w = s / 2;
    return Path()
      ..moveTo(c.dx, c.dy + w * 0.85)
      ..cubicTo(c.dx - w * 1.25, c.dy + w * 0.05, c.dx - w * 0.85, c.dy - w * 0.95, c.dx, c.dy - w * 0.35)
      ..cubicTo(c.dx + w * 0.85, c.dy - w * 0.95, c.dx + w * 1.25, c.dy + w * 0.05, c.dx, c.dy + w * 0.85)
      ..close();
  }
}

/// Loop helpers. Every motion in the scenes is a whole number of cycles per
/// controller period, so the loop is seamless.
abstract final class Loop {
  /// sin wave in -1..1 that completes [cycles] full turns while t goes 0→1.
  static double wave(double t, int cycles, [double phase = 0]) => math.sin((t * cycles + phase) * 2 * math.pi);

  /// 0..1 position that wraps [cycles] times while t goes 0→1.
  static double drift(double t, int cycles, [double start = 0]) {
    final v = (start + t * cycles) % 1.0;
    return v < 0 ? v + 1 : v;
  }
}
