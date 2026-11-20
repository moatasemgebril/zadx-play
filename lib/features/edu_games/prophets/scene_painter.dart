import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/catalog/prophets_quiz.dart';

/// Draws the scenery for a Heroes of the Prophets question.
///
/// STRICT: scenery and objects only (sea, ship, star, animals named in the
/// story...). Never draw a person, face, figure or character here.
class ProphetScenePainter extends CustomPainter {
  const ProphetScenePainter(this.scene);
  final ProphetScene scene;

  static const _daySky = [Color(0xFFBDEBFA), Color(0xFFE9F8FF)];
  static const _nightSky = [Color(0xFF0A225E), Color(0xFF2B2A6E)];
  static const _desertSky = [Color(0xFFFFE7B3), Color(0xFFFFF6E0)];
  static const _sea = Color(0xFF4CC9F0);
  static const _seaDeep = Color(0xFF1D7FB0);
  static const _sand = Color(0xFFF3D9A4);
  static const _grass = Color(0xFF7ED9B8);
  static const _wood = Color(0xFF8B5A2B);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    switch (scene) {
      case ProphetScene.ark:
        _sky(canvas, size, _daySky);
        _waves(canvas, size, h * 0.68, _sea);
        _ark(canvas, Offset(w * 0.5, h * 0.66), w * 0.42);
        _waves(canvas, size, h * 0.8, _seaDeep);
      case ProphetScene.whale:
        _sky(canvas, size, _daySky);
        _waves(canvas, size, h * 0.45, _sea);
        _whale(canvas, Offset(w * 0.5, h * 0.72), w * 0.3, const Color(0xFF1D4ED8));
      case ProphetScene.darkSea:
        _sky(canvas, size, _nightSky);
        _stars(canvas, size, 9, h * 0.35);
        _waves(canvas, size, h * 0.42, const Color(0xFF123A7A));
        _whale(canvas, Offset(w * 0.5, h * 0.72), w * 0.3, const Color(0xFF0B1F4A));
        canvas.drawCircle(Offset(w * 0.5, h * 0.7), w * 0.06, Paint()..color = AppColors.yellow.withValues(alpha: 0.35));
      case ProphetScene.splitSea:
        _sky(canvas, size, _daySky);
        canvas.drawRect(Rect.fromLTRB(0, h * 0.45, w, h), Paint()..color = _sand);
        final left = Path()
          ..moveTo(0, h * 0.2)
          ..quadraticBezierTo(w * 0.3, h * 0.15, w * 0.38, h * 0.3)
          ..lineTo(w * 0.42, h)
          ..lineTo(0, h)
          ..close();
        final right = Path()
          ..moveTo(w, h * 0.2)
          ..quadraticBezierTo(w * 0.7, h * 0.15, w * 0.62, h * 0.3)
          ..lineTo(w * 0.58, h)
          ..lineTo(w, h)
          ..close();
        final water = Paint()..color = _sea;
        canvas.drawPath(left, water);
        canvas.drawPath(right, water);
        final foam = Paint()
          ..color = Colors.white.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3;
        for (var i = 0; i < 4; i++) {
          final y = h * (0.4 + i * 0.15);
          canvas.drawLine(Offset(w * 0.05, y), Offset(w * 0.3, y - 6), foam);
          canvas.drawLine(Offset(w * 0.95, y), Offset(w * 0.7, y - 6), foam);
        }
      case ProphetScene.kaaba:
        _sky(canvas, size, _desertSky);
        canvas.drawRect(Rect.fromLTRB(0, h * 0.78, w, h), Paint()..color = const Color(0xFFEDE6DA));
        final front = Rect.fromLTRB(w * 0.32, h * 0.3, w * 0.62, h * 0.82);
        final side = Path()
          ..moveTo(front.right, front.top)
          ..lineTo(front.right + w * 0.1, front.top - h * 0.06)
          ..lineTo(front.right + w * 0.1, front.bottom - h * 0.06)
          ..lineTo(front.right, front.bottom)
          ..close();
        final top = Path()
          ..moveTo(front.left, front.top)
          ..lineTo(front.left + w * 0.1, front.top - h * 0.06)
          ..lineTo(front.right + w * 0.1, front.top - h * 0.06)
          ..lineTo(front.right, front.top)
          ..close();
        canvas.drawRect(front, Paint()..color = const Color(0xFF1A1A1A));
        canvas.drawPath(side, Paint()..color = const Color(0xFF2E2E2E));
        canvas.drawPath(top, Paint()..color = const Color(0xFF3A3A3A));
        final band = Paint()..color = AppColors.yellow;
        canvas.drawRect(Rect.fromLTRB(front.left, front.top + h * 0.1, front.right, front.top + h * 0.14), band);
        canvas.drawRect(Rect.fromLTRB(front.left + w * 0.19, front.top + h * 0.26, front.left + w * 0.25, front.top + h * 0.42), band);
      case ProphetScene.coolFire:
        _sky(canvas, size, _daySky);
        canvas.drawRect(Rect.fromLTRB(0, h * 0.75, w, h), Paint()..color = _grass);
        for (var i = 0; i < 5; i++) {
          final x = w * (0.3 + i * 0.1);
          _flame(canvas, Offset(x, h * 0.78), h * (i.isEven ? 0.42 : 0.32));
        }
        for (var i = 0; i < 9; i++) {
          final x = w * (0.08 + i * 0.105);
          _flower(canvas, Offset(x, h * 0.86 + (i.isEven ? 0 : 8)), i);
        }
      case ProphetScene.dreamSky:
        _sky(canvas, size, _nightSky);
        canvas.drawCircle(Offset(w * 0.18, h * 0.3), h * 0.12, Paint()..color = AppColors.yellow);
        _crescent(canvas, Offset(w * 0.82, h * 0.3), h * 0.11, const Color(0xFFFFF1C1));
        for (var i = 0; i < 11; i++) {
          final a = math.pi * (0.1 + 0.8 * i / 10);
          _star(canvas, Offset(w * 0.5 - math.cos(a) * w * 0.3, h * 0.85 - math.sin(a) * h * 0.45), 8, AppColors.yellow);
        }
      case ProphetScene.well:
        _sky(canvas, size, _desertSky);
        canvas.drawRect(Rect.fromLTRB(0, h * 0.7, w, h), Paint()..color = _sand);
        final body = Rect.fromLTRB(w * 0.36, h * 0.48, w * 0.64, h * 0.82);
        canvas.drawRect(body, Paint()..color = const Color(0xFFB9A58F));
        canvas.drawOval(Rect.fromLTRB(body.left, h * 0.42, body.right, h * 0.54), Paint()..color = const Color(0xFF8F7A63));
        canvas.drawOval(Rect.fromLTRB(body.left + 8, h * 0.445, body.right - 8, h * 0.515), Paint()..color = const Color(0xFF2B2118));
        final beam = Paint()
          ..color = _wood
          ..strokeWidth = 6;
        canvas.drawLine(Offset(body.left + 4, h * 0.48), Offset(body.left + 4, h * 0.18), beam);
        canvas.drawLine(Offset(body.right - 4, h * 0.48), Offset(body.right - 4, h * 0.18), beam);
        canvas.drawLine(Offset(body.left - 6, h * 0.18), Offset(body.right + 6, h * 0.18), beam);
        canvas.drawLine(
          Offset(w * 0.5, h * 0.18),
          Offset(w * 0.5, h * 0.36),
          Paint()
            ..color = const Color(0xFF6B4E00)
            ..strokeWidth = 2,
        );
        canvas.drawRect(Rect.fromCenter(center: Offset(w * 0.5, h * 0.39), width: 18, height: 14), Paint()..color = _wood);
      case ProphetScene.ant:
        _sky(canvas, size, _daySky);
        canvas.drawRect(Rect.fromLTRB(0, h * 0.62, w, h), Paint()..color = _grass);
        canvas.drawOval(Rect.fromLTRB(w * 0.62, h * 0.5, w * 0.92, h * 0.74), Paint()..color = const Color(0xFFC8A26B));
        canvas.drawOval(Rect.fromLTRB(w * 0.74, h * 0.57, w * 0.8, h * 0.63), Paint()..color = const Color(0xFF5A3E1B));
        _ant(canvas, Offset(w * 0.35, h * 0.72), h * 0.12);
        _ant(canvas, Offset(w * 0.12, h * 0.84), h * 0.07);
      case ProphetScene.hoopoe:
        _sky(canvas, size, _daySky);
        canvas.drawLine(
          Offset(w * 0.15, h * 0.78),
          Offset(w * 0.85, h * 0.72),
          Paint()
            ..color = _wood
            ..strokeWidth = 8
            ..strokeCap = StrokeCap.round,
        );
        _hoopoe(canvas, Offset(w * 0.5, h * 0.55), h * 0.17);
      case ProphetScene.garden:
        _sky(canvas, size, _daySky);
        _hills(canvas, size, _grass);
        _tree(canvas, Offset(w * 0.3, h * 0.78), h * 0.5);
        _tree(canvas, Offset(w * 0.72, h * 0.8), h * 0.38);
        for (var i = 0; i < 7; i++) {
          _flower(canvas, Offset(w * (0.1 + i * 0.13), h * 0.9), i);
        }
      case ProphetScene.night:
        _sky(canvas, size, _nightSky);
        _stars(canvas, size, 14, h * 0.7);
        _crescent(canvas, Offset(w * 0.75, h * 0.28), h * 0.14, const Color(0xFFFFF1C1));
        _hills(canvas, size, const Color(0xFF16336B));
      case ProphetScene.camel:
        _sky(canvas, size, _desertSky);
        canvas.drawCircle(Offset(w * 0.82, h * 0.22), h * 0.1, Paint()..color = AppColors.yellow);
        _hills(canvas, size, _sand);
        _camel(canvas, Offset(w * 0.48, h * 0.7), h * 0.5);
      case ProphetScene.iron:
        _sky(canvas, size, const [Color(0xFFFFE9D6), Color(0xFFFFF8F0)]);
        canvas.drawRect(Rect.fromLTRB(0, h * 0.8, w, h), Paint()..color = const Color(0xFFD9CFC2));
        _armour(canvas, Offset(w * 0.5, h * 0.5), h * 0.62);
      case ProphetScene.sunrise:
        _sky(canvas, size, const [Color(0xFFFFC3A0), Color(0xFFFFF1C1)]);
        final sun = Offset(w * 0.5, h * 0.7);
        final rays = Paint()
          ..color = AppColors.yellow.withValues(alpha: 0.6)
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round;
        for (var i = 0; i < 9; i++) {
          final a = math.pi + math.pi * i / 8;
          canvas.drawLine(sun + Offset(math.cos(a), math.sin(a)) * h * 0.24, sun + Offset(math.cos(a), math.sin(a)) * h * 0.36, rays);
        }
        canvas.drawCircle(sun, h * 0.2, Paint()..color = AppColors.yellow);
        _hills(canvas, size, _grass);
    }
  }

  // ---- building blocks -------------------------------------------------

  void _sky(Canvas canvas, Size size, List<Color> colors) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(rect),
    );
  }

  void _waves(Canvas canvas, Size size, double top, Color color) {
    final p = Path()..moveTo(0, top);
    const n = 6;
    final seg = size.width / n;
    for (var i = 0; i < n; i++) {
      p.quadraticBezierTo(seg * i + seg / 2, top - 12, seg * (i + 1), top);
    }
    p
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _hills(Canvas canvas, Size size, Color color) {
    final h = size.height;
    final p = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(size.width * 0.25, h * 0.68, size.width * 0.5, h * 0.8)
      ..quadraticBezierTo(size.width * 0.75, h * 0.9, size.width, h * 0.76)
      ..lineTo(size.width, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _stars(Canvas canvas, Size size, int count, double maxY) {
    final r = math.Random(count);
    for (var i = 0; i < count; i++) {
      _star(canvas, Offset(r.nextDouble() * size.width, r.nextDouble() * maxY), 3 + r.nextDouble() * 4, Colors.white);
    }
  }

  void _star(Canvas canvas, Offset c, double r, Color color) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    canvas.drawPath(p..close(), Paint()..color = color);
  }

  void _crescent(Canvas canvas, Offset c, double r, Color color) {
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: r)),
      Path()..addOval(Rect.fromCircle(center: c + Offset(r * 0.45, -r * 0.2), radius: r * 0.85)),
    );
    canvas.drawPath(moon, Paint()..color = color);
  }

  void _ark(Canvas canvas, Offset c, double halfWidth) {
    final hull = Path()
      ..moveTo(c.dx - halfWidth, c.dy - halfWidth * 0.25)
      ..lineTo(c.dx + halfWidth, c.dy - halfWidth * 0.25)
      ..lineTo(c.dx + halfWidth * 0.75, c.dy + halfWidth * 0.2)
      ..lineTo(c.dx - halfWidth * 0.75, c.dy + halfWidth * 0.2)
      ..close();
    canvas.drawPath(hull, Paint()..color = _wood);
    final plank = Paint()
      ..color = const Color(0xFF6B4420)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(c.dx - halfWidth * 0.9, c.dy - halfWidth * 0.08), Offset(c.dx + halfWidth * 0.9, c.dy - halfWidth * 0.08), plank);
    final cabin = Rect.fromLTRB(c.dx - halfWidth * 0.45, c.dy - halfWidth * 0.6, c.dx + halfWidth * 0.45, c.dy - halfWidth * 0.25);
    canvas.drawRect(cabin, Paint()..color = const Color(0xFFC08A55));
    final roof = Path()
      ..moveTo(cabin.left - 8, cabin.top)
      ..lineTo(c.dx, cabin.top - halfWidth * 0.22)
      ..lineTo(cabin.right + 8, cabin.top)
      ..close();
    canvas.drawPath(roof, Paint()..color = const Color(0xFF6B4420));
    for (var i = -1; i <= 1; i++) {
      canvas.drawCircle(Offset(c.dx + i * halfWidth * 0.25, cabin.center.dy), halfWidth * 0.06, Paint()..color = AppColors.yellow);
    }
  }

  void _whale(Canvas canvas, Offset c, double r, Color color) {
    final paint = Paint()..color = color;
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 1.05), paint);
    final tail = Path()
      ..moveTo(c.dx + r * 0.85, c.dy)
      ..lineTo(c.dx + r * 1.35, c.dy - r * 0.45)
      ..lineTo(c.dx + r * 1.2, c.dy)
      ..lineTo(c.dx + r * 1.35, c.dy + r * 0.3)
      ..close();
    canvas.drawPath(tail, paint);
    canvas.drawCircle(Offset(c.dx - r * 0.55, c.dy - r * 0.1), r * 0.06, Paint()..color = Colors.white);
    final spout = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final top = Offset(c.dx - r * 0.2, c.dy - r * 0.55);
    canvas.drawLine(top, top - Offset(0, r * 0.3), spout);
    canvas.drawLine(top - Offset(0, r * 0.3), top - Offset(r * 0.15, r * 0.4), spout);
    canvas.drawLine(top - Offset(0, r * 0.3), top - Offset(-r * 0.15, r * 0.4), spout);
  }

  void _flame(Canvas canvas, Offset base, double height) {
    final w = height * 0.35;
    final p = Path()
      ..moveTo(base.dx - w, base.dy)
      ..quadraticBezierTo(base.dx - w * 1.1, base.dy - height * 0.5, base.dx, base.dy - height)
      ..quadraticBezierTo(base.dx + w * 1.1, base.dy - height * 0.5, base.dx + w, base.dy)
      ..close();
    // Soft, calm colours: this fire was made cool and safe.
    canvas.drawPath(p, Paint()..color = const Color(0xFFFFB37A).withValues(alpha: 0.85));
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - w * 0.5, base.dy)
        ..quadraticBezierTo(base.dx, base.dy - height * 0.9, base.dx + w * 0.5, base.dy)
        ..close(),
      Paint()..color = const Color(0xFFFFE29A),
    );
  }

  void _flower(Canvas canvas, Offset c, int i) {
    const colors = [AppColors.coral, AppColors.purple, Colors.white, AppColors.sky];
    canvas.drawLine(
      c,
      c + const Offset(0, 14),
      Paint()
        ..color = AppColors.mint
        ..strokeWidth = 2,
    );
    for (var k = 0; k < 5; k++) {
      final a = k * math.pi * 2 / 5;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * 5, 4, Paint()..color = colors[i % colors.length]);
    }
    canvas.drawCircle(c, 3, Paint()..color = AppColors.yellow);
  }

  void _tree(Canvas canvas, Offset base, double height) {
    canvas.drawRect(Rect.fromLTRB(base.dx - height * 0.05, base.dy - height * 0.5, base.dx + height * 0.05, base.dy), Paint()..color = _wood);
    final leaf = Paint()..color = AppColors.mint;
    canvas.drawCircle(Offset(base.dx, base.dy - height * 0.68), height * 0.28, leaf);
    canvas.drawCircle(Offset(base.dx - height * 0.2, base.dy - height * 0.55), height * 0.2, leaf);
    canvas.drawCircle(Offset(base.dx + height * 0.2, base.dy - height * 0.55), height * 0.2, leaf);
  }

  void _ant(Canvas canvas, Offset c, double s) {
    final body = Paint()..color = const Color(0xFF3B2A1A);
    final leg = Paint()
      ..color = const Color(0xFF3B2A1A)
      ..strokeWidth = s * 0.06
      ..strokeCap = StrokeCap.round;
    for (var i = -1; i <= 1; i++) {
      final x = c.dx + i * s * 0.18;
      canvas.drawLine(Offset(x, c.dy), Offset(x - s * 0.15, c.dy + s * 0.45), leg);
      canvas.drawLine(Offset(x, c.dy), Offset(x + s * 0.15, c.dy + s * 0.45), leg);
    }
    canvas.drawOval(Rect.fromCenter(center: c + Offset(s * 0.55, 0), width: s * 0.75, height: s * 0.5), body);
    canvas.drawOval(Rect.fromCenter(center: c, width: s * 0.4, height: s * 0.3), body);
    final head = c - Offset(s * 0.42, s * 0.05);
    canvas.drawCircle(head, s * 0.18, body);
    canvas.drawLine(head, head + Offset(-s * 0.2, -s * 0.35), leg);
    canvas.drawLine(head, head + Offset(-s * 0.02, -s * 0.38), leg);
  }

  void _hoopoe(Canvas canvas, Offset c, double s) {
    final body = Paint()..color = const Color(0xFFE59A5B);
    canvas.drawOval(Rect.fromCenter(center: c, width: s * 1.6, height: s), body);
    final wing = Path()
      ..moveTo(c.dx - s * 0.2, c.dy - s * 0.2)
      ..lineTo(c.dx + s * 0.9, c.dy - s * 0.05)
      ..lineTo(c.dx + s * 0.2, c.dy + s * 0.35)
      ..close();
    canvas.drawPath(wing, Paint()..color = const Color(0xFF222222));
    final stripe = Paint()
      ..color = Colors.white
      ..strokeWidth = s * 0.06;
    for (var i = 0; i < 3; i++) {
      final x = c.dx + s * (0.05 + i * 0.22);
      canvas.drawLine(Offset(x, c.dy - s * 0.12), Offset(x - s * 0.1, c.dy + s * 0.18), stripe);
    }
    final head = c - Offset(s * 0.85, s * 0.35);
    canvas.drawCircle(head, s * 0.3, body);
    for (var i = 0; i < 5; i++) {
      final a = -math.pi * (0.35 + i * 0.12);
      final tip = head + Offset(math.cos(a), math.sin(a)) * s * 0.75;
      canvas.drawLine(
        head,
        tip,
        Paint()
          ..color = const Color(0xFFE59A5B)
          ..strokeWidth = s * 0.12
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(tip, s * 0.06, Paint()..color = const Color(0xFF222222));
    }
    canvas.drawLine(
      head - Offset(s * 0.25, 0),
      head - Offset(s * 0.85, -s * 0.12),
      Paint()
        ..color = const Color(0xFF3B2A1A)
        ..strokeWidth = s * 0.07
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(head - Offset(s * 0.08, s * 0.05), s * 0.05, Paint()..color = const Color(0xFF222222));
    final leg = Paint()
      ..color = const Color(0xFF3B2A1A)
      ..strokeWidth = s * 0.06;
    canvas.drawLine(c + Offset(-s * 0.1, s * 0.45), c + Offset(-s * 0.1, s * 0.95), leg);
    canvas.drawLine(c + Offset(s * 0.15, s * 0.45), c + Offset(s * 0.15, s * 0.9), leg);
  }

  void _camel(Canvas canvas, Offset c, double s) {
    final paint = Paint()..color = const Color(0xFFC08A55);
    final leg = Paint()
      ..color = const Color(0xFFA9743F)
      ..strokeWidth = s * 0.07
      ..strokeCap = StrokeCap.round;
    for (final dx in [-0.32, -0.2, 0.2, 0.32]) {
      canvas.drawLine(c + Offset(s * dx, 0), c + Offset(s * dx, s * 0.42), leg);
    }
    canvas.drawOval(Rect.fromCenter(center: c, width: s * 0.9, height: s * 0.4), paint);
    canvas.drawOval(Rect.fromCenter(center: c - Offset(0, s * 0.2), width: s * 0.45, height: s * 0.35), paint);
    final neck = Paint()
      ..color = const Color(0xFFC08A55)
      ..strokeWidth = s * 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - Offset(s * 0.4, s * 0.02), c - Offset(s * 0.58, s * 0.35), neck);
    canvas.drawOval(Rect.fromCenter(center: c - Offset(s * 0.66, s * 0.38), width: s * 0.26, height: s * 0.14), paint);
    canvas.drawCircle(c - Offset(s * 0.64, s * 0.41), s * 0.018, Paint()..color = const Color(0xFF3B2A1A));
    canvas.drawLine(
      c + Offset(s * 0.45, -s * 0.02),
      c + Offset(s * 0.52, s * 0.18),
      Paint()
        ..color = const Color(0xFFA9743F)
        ..strokeWidth = s * 0.03,
    );
  }

  void _armour(Canvas canvas, Offset c, double s) {
    final p = Path()
      ..moveTo(c.dx - s * 0.18, c.dy - s * 0.45)
      ..quadraticBezierTo(c.dx, c.dy - s * 0.32, c.dx + s * 0.18, c.dy - s * 0.45)
      ..lineTo(c.dx + s * 0.42, c.dy - s * 0.35)
      ..lineTo(c.dx + s * 0.34, c.dy - s * 0.05)
      ..lineTo(c.dx + s * 0.3, c.dy + s * 0.45)
      ..lineTo(c.dx - s * 0.3, c.dy + s * 0.45)
      ..lineTo(c.dx - s * 0.34, c.dy - s * 0.05)
      ..lineTo(c.dx - s * 0.42, c.dy - s * 0.35)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFF9AA3AE));
    canvas.save();
    canvas.clipPath(p);
    final ring = Paint()
      ..color = const Color(0xFF6B7480)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final step = s * 0.06;
    var row = 0;
    for (var y = c.dy - s * 0.5; y < c.dy + s * 0.5; y += step * 0.8) {
      final shift = row.isEven ? 0.0 : step / 2;
      for (var x = c.dx - s * 0.5 + shift; x < c.dx + s * 0.5; x += step) {
        canvas.drawCircle(Offset(x, y), step * 0.4, ring);
      }
      row++;
    }
    canvas.restore();
    canvas.drawPath(
      p,
      Paint()
        ..color = const Color(0xFF4B5563)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(ProphetScenePainter oldDelegate) => oldDelegate.scene != scene;
}
