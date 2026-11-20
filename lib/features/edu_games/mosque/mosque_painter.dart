import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/catalog/mosque_parts.dart';

/// Draws the mosque with the first [built] parts of [mosqueParts].
/// The next part (if any) is drawn faintly as a hint of what comes next.
class MosquePainter extends CustomPainter {
  MosquePainter({required this.built, this.showNextHint = true});

  final int built;
  final bool showNextHint;

  static const _stone = Color(0xFFB9A58F);
  static const _wall = Color(0xFFFFF8F0);
  static const _gold = AppColors.yellow;
  static const _grass = Color(0xFF7ED9B8);
  static const _grassDark = AppColors.mint;

  /// Paint order (back to front) — not the same as the build order.
  static const _zOrder = ['garden', 'foundation', 'minaret', 'walls', 'windows', 'door', 'dome', 'crescent', 'lanterns', 'carpet'];

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Geo(size);
    // Ground.
    canvas.drawRect(Rect.fromLTRB(0, g.ground, size.width, size.height), Paint()..color = const Color(0xFFF3E3C7));

    for (final id in _zOrder) {
      final index = mosqueParts.indexWhere((p) => p.id == id);
      if (index < 0) continue;
      if (index < built) {
        _draw(canvas, g, id);
      } else if (showNextHint && index == built) {
        canvas.saveLayer(Offset.zero & size, Paint()..color = const Color(0x40000000));
        _draw(canvas, g, id);
        canvas.restore();
      }
    }
    // Garden bushes go in front of everything.
    final gardenIndex = mosqueParts.indexWhere((p) => p.id == 'garden');
    if (gardenIndex < built) _bushes(canvas, g);
  }

  void _draw(Canvas canvas, _Geo g, String id) {
    switch (id) {
      case 'foundation':
        final r = Rect.fromLTRB(g.w * 0.16, g.ground - g.h * 0.06, g.w * 0.84, g.ground);
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)), Paint()..color = _stone);
        final line = Paint()
          ..color = const Color(0xFF8F7A63)
          ..strokeWidth = 1.5;
        canvas.drawLine(Offset(r.left, r.center.dy), Offset(r.right, r.center.dy), line);
        for (var x = r.left + 18; x < r.right; x += 36) {
          canvas.drawLine(Offset(x, r.top), Offset(x, r.center.dy), line);
          canvas.drawLine(Offset(x + 18, r.center.dy), Offset(x + 18, r.bottom), line);
        }
      case 'walls':
        final r = g.walls;
        canvas.drawRect(r, Paint()..color = _wall);
        canvas.drawRect(
          r,
          Paint()
            ..color = AppColors.purpleSoft
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        canvas.drawRect(Rect.fromLTRB(r.left, r.top, r.right, r.top + g.h * 0.03), Paint()..color = AppColors.purple);
        // Little crenellations along the top.
        final cren = Paint()..color = AppColors.purple;
        for (var x = r.left; x < r.right - 4; x += g.w * 0.05) {
          canvas.drawRect(Rect.fromLTWH(x, r.top - g.h * 0.02, g.w * 0.025, g.h * 0.02), cren);
        }
      case 'door':
        final d = Rect.fromCenter(
          center: Offset(g.cx, g.walls.bottom - g.h * 0.11),
          width: g.w * 0.15,
          height: g.h * 0.22,
        );
        final path = _arch(d);
        canvas.drawPath(path, Paint()..color = AppColors.purpleDark);
        canvas.drawPath(
          path,
          Paint()
            ..color = _gold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
        canvas.drawCircle(Offset(d.center.dx + d.width * 0.25, d.center.dy + d.height * 0.15), 3, Paint()..color = _gold);
      case 'windows':
        for (final fx in [0.31, 0.69]) {
          final wRect = Rect.fromCenter(center: Offset(g.w * fx, g.walls.top + g.h * 0.13), width: g.w * 0.1, height: g.h * 0.12);
          final path = _arch(wRect);
          canvas.drawPath(path, Paint()..color = AppColors.sky);
          canvas.drawPath(
            path,
            Paint()
              ..color = AppColors.purple
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3,
          );
          canvas.drawLine(
            Offset(wRect.center.dx, wRect.top + wRect.width / 2),
            Offset(wRect.center.dx, wRect.bottom),
            Paint()
              ..color = AppColors.purple
              ..strokeWidth = 2,
          );
        }
      case 'dome':
        final base = g.walls.top - g.h * 0.02;
        final r = g.w * 0.19;
        final path = Path()
          ..moveTo(g.cx - r, base)
          ..cubicTo(g.cx - r * 1.1, base - r * 0.9, g.cx - r * 0.25, base - r * 1.1, g.cx, base - r * 1.45)
          ..cubicTo(g.cx + r * 0.25, base - r * 1.1, g.cx + r * 1.1, base - r * 0.9, g.cx + r, base)
          ..close();
        canvas.drawRect(Rect.fromLTRB(g.cx - r * 1.05, base, g.cx + r * 1.05, base + g.h * 0.02), Paint()..color = AppColors.purple);
        canvas.drawPath(path, Paint()..color = _gold);
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFFE0A800)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      case 'minaret':
        final left = g.w * 0.86;
        final right = g.w * 0.95;
        final top = g.h * 0.2;
        canvas.drawRect(Rect.fromLTRB(left, top, right, g.ground), Paint()..color = _wall);
        canvas.drawRect(
          Rect.fromLTRB(left, top, right, g.ground),
          Paint()
            ..color = AppColors.purpleSoft
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        final band = Paint()..color = AppColors.purple;
        canvas.drawRect(Rect.fromLTRB(left - 6, g.h * 0.32, right + 6, g.h * 0.345), band);
        canvas.drawRect(Rect.fromLTRB(left, g.h * 0.55, right, g.h * 0.565), band);
        final cap = Path()
          ..moveTo(left - 2, top)
          ..quadraticBezierTo((left + right) / 2, top - g.h * 0.12, right + 2, top)
          ..close();
        canvas.drawPath(cap, Paint()..color = _gold);
      case 'crescent':
        final base = g.walls.top - g.h * 0.02;
        final tip = Offset(g.cx, base - g.w * 0.19 * 1.45);
        canvas.drawLine(
          tip,
          tip - Offset(0, g.h * 0.05),
          Paint()
            ..color = const Color(0xFFE0A800)
            ..strokeWidth = 3,
        );
        final c = tip - Offset(0, g.h * 0.085);
        final rr = g.w * 0.04;
        final moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: c, radius: rr)),
          Path()..addOval(Rect.fromCircle(center: c + Offset(rr * 0.45, -rr * 0.15), radius: rr * 0.85)),
        );
        canvas.drawPath(moon, Paint()..color = _gold);
      case 'carpet':
        final top = g.ground - 2;
        final rug = Path()
          ..moveTo(g.cx - g.w * 0.08, top)
          ..lineTo(g.cx + g.w * 0.08, top)
          ..lineTo(g.cx + g.w * 0.13, g.h * 0.985)
          ..lineTo(g.cx - g.w * 0.13, g.h * 0.985)
          ..close();
        canvas.drawPath(rug, Paint()..color = AppColors.coral);
        canvas.drawPath(
          rug,
          Paint()
            ..color = _gold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      case 'lanterns':
        for (final fx in [0.23, 0.395, 0.605, 0.77]) {
          final x = g.w * fx;
          final y0 = g.walls.top + g.h * 0.03;
          final y1 = y0 + g.h * 0.02;
          canvas.drawLine(
            Offset(x, y0),
            Offset(x, y1),
            Paint()
              ..color = AppColors.ink
              ..strokeWidth = 1.5,
          );
          canvas.drawCircle(Offset(x, y1 + 9), 14, Paint()..color = _gold.withValues(alpha: 0.35));
          final body = Path()
            ..moveTo(x, y1)
            ..lineTo(x + 7, y1 + 6)
            ..lineTo(x + 7, y1 + 14)
            ..lineTo(x, y1 + 20)
            ..lineTo(x - 7, y1 + 14)
            ..lineTo(x - 7, y1 + 6)
            ..close();
          canvas.drawPath(body, Paint()..color = AppColors.coral);
          canvas.drawCircle(Offset(x, y1 + 10), 3.5, Paint()..color = _gold);
        }
      case 'garden':
        canvas.drawRect(Rect.fromLTRB(0, g.ground, g.w, g.h), Paint()..color = _grass);
    }
  }

  void _bushes(Canvas canvas, _Geo g) {
    final bush = Paint()..color = _grassDark;
    for (final fx in [0.06, 0.2, 0.74]) {
      final c = Offset(g.w * fx, g.ground + g.h * 0.02);
      canvas.drawCircle(c, g.w * 0.045, bush);
      canvas.drawCircle(c + Offset(g.w * 0.04, 0), g.w * 0.035, bush);
    }
    const flowerColors = [AppColors.coral, AppColors.yellow, AppColors.purple, Colors.white];
    final rnd = math.Random(3);
    for (var i = 0; i < 12; i++) {
      final dx = g.w * (0.03 + rnd.nextDouble() * 0.94);
      if ((dx - g.cx).abs() < g.w * 0.15) continue; // keep the path to the door clear
      final c = Offset(dx, g.ground + g.h * (0.05 + rnd.nextDouble() * 0.07));
      canvas.drawCircle(c, 4, Paint()..color = flowerColors[i % flowerColors.length]);
    }
  }

  /// A rectangle with a rounded (arched) top.
  Path _arch(Rect r) {
    final rad = r.width / 2;
    return Path()
      ..moveTo(r.left, r.bottom)
      ..lineTo(r.left, r.top + rad)
      ..arcToPoint(Offset(r.right, r.top + rad), radius: Radius.circular(rad))
      ..lineTo(r.right, r.bottom)
      ..close();
  }

  @override
  bool shouldRepaint(MosquePainter oldDelegate) => oldDelegate.built != built || oldDelegate.showNextHint != showNextHint;
}

class _Geo {
  _Geo(Size s)
      : w = s.width,
        h = s.height;

  final double w;
  final double h;

  double get cx => w * 0.5;
  double get ground => h * 0.86;

  /// The prayer hall walls (sit on the foundation).
  Rect get walls => Rect.fromLTRB(w * 0.2, h * 0.47, w * 0.8, ground - h * 0.06);
}
