import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'art_shapes.dart';

/// The Zad X icon set: original, rounded, two-tone, drawn in code on a 24×24
/// grid. Shapes are objects and architecture only (no figures).
///
/// Zad X Kids ([artReligiousMotifs] false): [ZadIconKind.prayer] is drawn as an alarm clock
/// (a schedule) and [ZadIconKind.quran] as an open storybook without the stand. No dome, no
/// crescent, no Arabic script.
enum ZadIconKind { home, games, tasks, quran, prayer, parent, settings, help, star }

/// Colour treatment of an icon.
enum ZadIconTone {
  /// Full brand colours (selected tab, cards on light backgrounds).
  brand,

  /// Quiet two-tone for unselected tabs (≥ 3:1 outline on white).
  muted,

  /// White + gold for the navy header and purple panels.
  onDark,
}

@immutable
class ZadIconColors {
  const ZadIconColors({required this.primary, required this.accent, required this.detail, required this.outline});
  final Color primary;
  final Color accent;
  final Color detail;
  final Color outline;

  static const _purple = Color(0xFF6C3BEB);
  static const _purpleDark = Color(0xFF4C1DB8);
  static const _gold = Color(0xFFFFC83D);
  static const _coral = Color(0xFFFF6B6B);
  static const _sky = Color(0xFF4CC9F0);
  static const _green = Color(0xFF2DBE7E);
  static const _greenDeep = Color(0xFF065F55);
  static const _navy = Color(0xFF0A225E);
  static const _blue = Color(0xFF1D4ED8);
  static const _white = Color(0xFFFFFFFF);
  static const _brown = Color(0xFF6B4E00);
  static const _wine = Color(0xFF9B1C2E);

  static ZadIconColors of(ZadIconKind kind, ZadIconTone tone) => switch (tone) {
        ZadIconTone.muted => const ZadIconColors(
            primary: Color(0xFFE4DEF5),
            accent: Color(0xFFC9C2E6),
            detail: Color(0xFF5E5A78),
            outline: Color(0xFF5E5A78),
          ),
        ZadIconTone.onDark => const ZadIconColors(primary: _white, accent: _gold, detail: _navy, outline: Color(0x00000000)),
        ZadIconTone.brand => switch (kind) {
            ZadIconKind.home => const ZadIconColors(primary: _sky, accent: _coral, detail: _gold, outline: _navy),
            ZadIconKind.games => const ZadIconColors(primary: _coral, accent: _gold, detail: _white, outline: _wine),
            ZadIconKind.tasks => const ZadIconColors(primary: _gold, accent: _purple, detail: _purple, outline: _brown),
            ZadIconKind.quran => const ZadIconColors(primary: _green, accent: _gold, detail: _white, outline: _greenDeep),
            ZadIconKind.prayer => const ZadIconColors(primary: _purple, accent: _gold, detail: _white, outline: _purpleDark),
            ZadIconKind.parent => const ZadIconColors(primary: _blue, accent: _gold, detail: _white, outline: _navy),
            ZadIconKind.settings => const ZadIconColors(primary: _purple, accent: _gold, detail: _white, outline: _purpleDark),
            ZadIconKind.help => const ZadIconColors(primary: _sky, accent: _gold, detail: _navy, outline: _navy),
            ZadIconKind.star => const ZadIconColors(primary: _gold, accent: _white, detail: _white, outline: _brown),
          },
      };

  @override
  bool operator ==(Object other) =>
      other is ZadIconColors &&
      other.primary == primary &&
      other.accent == accent &&
      other.detail == detail &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(primary, accent, detail, outline);
}

/// A Zad X icon. Decorative unless [semanticLabel] is given.
///
/// With [bounce], the icon pops in gently once when it first appears (used
/// for the selected tab). The bounce is skipped when reduce-motion is on.
class ZadIcon extends StatefulWidget {
  const ZadIcon(this.kind, {super.key, this.size = 24, this.tone = ZadIconTone.brand, this.bounce = false, this.semanticLabel});

  final ZadIconKind kind;
  final double size;
  final ZadIconTone tone;
  final bool bounce;
  final String? semanticLabel;

  @override
  State<ZadIcon> createState() => _ZadIconState();
}

class _ZadIconState extends State<ZadIcon> with SingleTickerProviderStateMixin {
  AnimationController? _pop;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !widget.bounce) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..forward();
  }

  @override
  void dispose() {
    _pop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget icon = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: ZadIconPainter(widget.kind, ZadIconColors.of(widget.kind, widget.tone))),
    );
    final pop = _pop;
    if (pop != null) {
      icon = AnimatedBuilder(
        animation: pop,
        builder: (context, child) => Transform.scale(
          scale: 0.8 + 0.2 * Curves.easeOutBack.transform(pop.value),
          child: child,
        ),
        child: icon,
      );
    }
    final label = widget.semanticLabel;
    return label == null ? ExcludeSemantics(child: icon) : Semantics(label: label, image: true, child: icon);
  }
}

class ZadIconPainter extends CustomPainter {
  const ZadIconPainter(this.kind, this.colors, {this.religiousMotifs = artReligiousMotifs});
  final ZadIconKind kind;
  final ZadIconColors colors;

  /// False in Zad X Kids: neutral shapes for the prayer and Quran icons.
  final bool religiousMotifs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    switch (kind) {
      case ZadIconKind.home:
        _home(canvas);
      case ZadIconKind.games:
        _games(canvas);
      case ZadIconKind.tasks:
        _tasks(canvas);
      case ZadIconKind.quran:
        religiousMotifs ? _quran(canvas) : _storybook(canvas);
      case ZadIconKind.prayer:
        religiousMotifs ? _prayer(canvas) : _clock(canvas);
      case ZadIconKind.parent:
        _parent(canvas);
      case ZadIconKind.settings:
        _settings(canvas);
      case ZadIconKind.help:
        _help(canvas);
      case ZadIconKind.star:
        _star(canvas);
    }
    canvas.restore();
  }

  Paint _fill(Color c) => Paint()
    ..color = c
    ..isAntiAlias = true;

  Paint _stroke(Color c, [double w = 1.4]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..isAntiAlias = true;

  /// Fills [p] then draws the outline (skipped when the outline is clear).
  void _shape(Canvas canvas, Path p, Color c) {
    canvas.drawPath(p, _fill(c));
    if (colors.outline.a > 0) canvas.drawPath(p, _stroke(colors.outline));
  }

  void _home(Canvas canvas) {
    _shape(canvas, Path()..addRRect(RRect.fromLTRBR(5, 10.5, 19, 21, const Radius.circular(2.5))), colors.primary);
    final roof = Path()
      ..moveTo(2.6, 11.6)
      ..lineTo(12, 3.4)
      ..lineTo(21.4, 11.6)
      ..lineTo(19.6, 13)
      ..lineTo(12, 6.6)
      ..lineTo(4.4, 13)
      ..close();
    _shape(canvas, roof, colors.accent);
    canvas.drawRRect(ArtShapes.arch(const Rect.fromLTWH(10, 14.5, 4, 6.5)), _fill(colors.detail));
  }

  void _games(Canvas canvas) {
    final body = Path()
      ..addRRect(RRect.fromLTRBR(2.5, 7, 21.5, 18, const Radius.circular(5.5)));
    _shape(canvas, body, colors.primary);
    final d = _fill(colors.detail);
    canvas.drawRRect(RRect.fromLTRBR(5.4, 11.7, 10.6, 13.3, const Radius.circular(0.8)), d);
    canvas.drawRRect(RRect.fromLTRBR(7.2, 9.9, 8.8, 15.1, const Radius.circular(0.8)), d);
    canvas.drawCircle(const Offset(15.6, 11), 1.5, _fill(colors.accent));
    canvas.drawCircle(const Offset(18, 13.8), 1.5, _fill(colors.accent));
  }

  void _tasks(Canvas canvas) {
    _shape(canvas, Path()..addRRect(RRect.fromLTRBR(4.5, 4, 19.5, 21.5, const Radius.circular(3))), colors.primary);
    _shape(canvas, Path()..addRRect(RRect.fromLTRBR(8.5, 2.3, 15.5, 6, const Radius.circular(1.6))), colors.accent);
    final check = Path()
      ..moveTo(8.3, 13.4)
      ..lineTo(11, 16.1)
      ..lineTo(15.9, 10.4);
    canvas.drawPath(check, _stroke(colors.detail, 2.2));
  }

  void _quran(Canvas canvas) {
    // Stand (rehal) first, the open book rests on it.
    final stand = _stroke(colors.accent, 2);
    canvas.drawLine(const Offset(7, 21), const Offset(17, 16), stand);
    canvas.drawLine(const Offset(17, 21), const Offset(7, 16), stand);
    final left = Path()
      ..moveTo(12, 7)
      ..quadraticBezierTo(7.5, 4.6, 2.8, 5.8)
      ..lineTo(2.8, 16.6)
      ..quadraticBezierTo(7.5, 15.4, 12, 17.6)
      ..close();
    final right = Path()
      ..moveTo(12, 7)
      ..quadraticBezierTo(16.5, 4.6, 21.2, 5.8)
      ..lineTo(21.2, 16.6)
      ..quadraticBezierTo(16.5, 15.4, 12, 17.6)
      ..close();
    _shape(canvas, left, colors.primary);
    _shape(canvas, right, colors.primary);
    final lines = _stroke(colors.detail, 1);
    for (final y in [9.0, 11.5, 14.0]) {
      canvas.drawLine(Offset(5, y), Offset(10, y + 0.6), lines);
      canvas.drawLine(Offset(14, y + 0.6), Offset(19, y), lines);
    }
  }

  void _prayer(Canvas canvas) {
    _shape(canvas, Path()..addRRect(RRect.fromLTRBR(4.5, 13, 19.5, 21.5, const Radius.circular(1.8))), colors.primary);
    _shape(canvas, ArtShapes.dome(const Offset(5.5, 13.2), 13, 5.6), colors.primary);
    canvas.drawPath(ArtShapes.crescent(const Offset(12, 3.2), 1.9), _fill(colors.accent));
    canvas.drawRRect(ArtShapes.arch(const Rect.fromLTWH(10.2, 16, 3.6, 5.5)), _fill(colors.detail));
  }

  /// Zad X Kids: an open storybook (no stand), with a bookmark ribbon.
  void _storybook(Canvas canvas) {
    final left = Path()
      ..moveTo(12, 6.5)
      ..quadraticBezierTo(7.5, 4.2, 2.6, 5.4)
      ..lineTo(2.6, 18.2)
      ..quadraticBezierTo(7.5, 17, 12, 19.4)
      ..close();
    final right = Path()
      ..moveTo(12, 6.5)
      ..quadraticBezierTo(16.5, 4.2, 21.4, 5.4)
      ..lineTo(21.4, 18.2)
      ..quadraticBezierTo(16.5, 17, 12, 19.4)
      ..close();
    _shape(canvas, left, colors.primary);
    _shape(canvas, right, colors.primary);
    final lines = _stroke(colors.detail, 1);
    for (final y in [9.0, 11.6, 14.2]) {
      canvas.drawLine(Offset(4.8, y), Offset(10, y + 0.6), lines);
      canvas.drawLine(Offset(14, y + 0.6), Offset(19.2, y), lines);
    }
    final ribbon = Path()
      ..moveTo(15.6, 5.6)
      ..lineTo(17.8, 5.6)
      ..lineTo(17.8, 10.4)
      ..lineTo(16.7, 9.4)
      ..lineTo(15.6, 10.4)
      ..close();
    canvas.drawPath(ribbon, _fill(colors.accent));
  }

  /// Zad X Kids: a friendly alarm clock (schedules).
  void _clock(Canvas canvas) {
    final bells = _fill(colors.accent);
    canvas.drawCircle(const Offset(6.2, 5.4), 2.6, bells);
    canvas.drawCircle(const Offset(17.8, 5.4), 2.6, bells);
    final legs = _stroke(colors.outline.a > 0 ? colors.outline : colors.accent, 1.8);
    canvas.drawLine(const Offset(7.6, 19.2), const Offset(5.8, 21.6), legs);
    canvas.drawLine(const Offset(16.4, 19.2), const Offset(18.2, 21.6), legs);
    _shape(canvas, Path()..addOval(Rect.fromCircle(center: const Offset(12, 13), radius: 8)), colors.primary);
    canvas.drawCircle(const Offset(12, 13), 5.6, _fill(colors.detail));
    final hands = _stroke(colors.primary, 1.6);
    canvas.drawLine(const Offset(12, 13), const Offset(12, 9.4), hands);
    canvas.drawLine(const Offset(12, 13), const Offset(14.6, 14.4), hands);
  }

  void _parent(Canvas canvas) {
    final shield = Path()
      ..moveTo(12, 2.4)
      ..lineTo(20, 5.4)
      ..lineTo(20, 11)
      ..cubicTo(20, 16, 16.4, 19.6, 12, 21.6)
      ..cubicTo(7.6, 19.6, 4, 16, 4, 11)
      ..lineTo(4, 5.4)
      ..close();
    _shape(canvas, shield, colors.primary);
    canvas.drawPath(ArtShapes.heart(const Offset(12, 11.6), 8), _fill(colors.accent));
  }

  void _settings(Canvas canvas) {
    const c = Offset(12, 12);
    final gear = Path();
    const teeth = 8;
    for (var i = 0; i < teeth * 4; i++) {
      final tooth = i ~/ 4;
      final step = i % 4;
      final base = tooth * 2 * math.pi / teeth;
      final (r, da) = switch (step) {
        0 => (7.0, -0.36),
        1 => (9.6, -0.2),
        2 => (9.6, 0.2),
        _ => (7.0, 0.36),
      };
      final p = c + Offset(math.cos(base + da), math.sin(base + da)) * r;
      if (i == 0) {
        gear.moveTo(p.dx, p.dy);
      } else {
        gear.lineTo(p.dx, p.dy);
      }
    }
    gear.close();
    _shape(canvas, gear, colors.primary);
    canvas.drawCircle(c, 3.2, _fill(colors.accent));
    if (colors.outline.a > 0) canvas.drawCircle(c, 3.2, _stroke(colors.outline));
  }

  void _help(Canvas canvas) {
    final bubble = Path()
      ..addRRect(RRect.fromLTRBR(2.8, 3.4, 21.2, 17.4, const Radius.circular(6)))
      ..moveTo(7, 16.6)
      ..lineTo(6, 21.2)
      ..lineTo(11.6, 17)
      ..close();
    _shape(canvas, bubble, colors.primary);
    final q = Path()
      ..moveTo(9.6, 8.8)
      ..arcTo(Rect.fromCircle(center: const Offset(12, 8.9), radius: 2.4), math.pi, math.pi * 1.35, false)
      ..lineTo(12, 12.2);
    canvas.drawPath(q, _stroke(colors.detail, 2));
    canvas.drawCircle(const Offset(12, 14.6), 1.15, _fill(colors.detail));
  }

  void _star(Canvas canvas) {
    _shape(canvas, ArtShapes.star(const Offset(12, 12.6), 10, inner: 0.5), colors.primary);
    canvas.drawOval(Rect.fromCenter(center: const Offset(10, 9.4), width: 3, height: 2), _fill(colors.accent.withValues(alpha: 0.7)));
  }

  @override
  bool shouldRepaint(ZadIconPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.colors != colors || oldDelegate.religiousMotifs != religiousMotifs;
}
