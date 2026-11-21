import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'art_shapes.dart';

/// A short, original burst of stars and confetti dots for rewards (task
/// done, stars earned). Plays once (1.2 s, always < 1.5 s), never flashes,
/// ignores touches and is hidden from screen readers.
///
/// With reduce-motion on, nothing moves: a still sprinkle of stars is shown
/// for the same short time, then removed.
class ZadCelebrationBurst extends StatefulWidget {
  const ZadCelebrationBurst({super.key, this.seed = 7, this.particles = 22, this.origin = const Alignment(0, -0.3), this.onDone});

  static const duration = Duration(milliseconds: 1200);

  final int seed;
  final int particles;

  /// Where the burst starts inside the widget's box.
  final Alignment origin;
  final VoidCallback? onDone;

  @override
  State<ZadCelebrationBurst> createState() => _ZadCelebrationBurstState();
}

class _ZadCelebrationBurstState extends State<ZadCelebrationBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: ZadCelebrationBurst.duration);
  bool _still = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() => _done = true);
        widget.onDone?.call();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_c.isAnimating && !_done) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.infinite,
            painter: BurstPainter(_c, seed: widget.seed, count: widget.particles, origin: widget.origin, still: _still),
          ),
        ),
      ),
    );
  }
}

class BurstPainter extends CustomPainter {
  BurstPainter(this.t, {required this.seed, required this.count, required this.origin, required this.still}) : super(repaint: t);
  final Animation<double> t;
  final int seed;
  final int count;
  final Alignment origin;
  final bool still;

  static const _colors = [
    Color(0xFFFFC83D),
    Color(0xFFFF6B6B),
    Color(0xFF4CC9F0),
    Color(0xFF2DBE7E),
    Color(0xFF6C3BEB),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final v = still ? 0.55 : t.value;
    final ease = Curves.easeOutCubic.transform(v);
    // Smooth fade-out over the last 35 %: one soft disappearance, no blinking.
    final alpha = still ? 0.9 : (v < 0.65 ? 1.0 : (1 - (v - 0.65) / 0.35).clamp(0.0, 1.0).toDouble());
    final c = origin.alongSize(size);
    final reach = size.shortestSide * 0.45;
    final r = math.Random(seed);
    for (var i = 0; i < count; i++) {
      final a = i * 2 * math.pi / count + r.nextDouble() * 0.4;
      final speed = 0.55 + r.nextDouble() * 0.45;
      final p = c + Offset(math.cos(a), math.sin(a)) * reach * speed * ease + Offset(0, reach * 0.35 * v * v);
      final color = _colors[i % _colors.length].withValues(alpha: alpha);
      final s = (5 + r.nextDouble() * 5) * (1 - 0.3 * v);
      if (i % 3 == 0) {
        canvas.drawCircle(p, s * 0.6, Paint()..color = color);
      } else {
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(v * math.pi * (i.isEven ? 1 : -1));
        canvas.drawPath(ArtShapes.star(Offset.zero, s), Paint()..color = color);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(BurstPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.still != still || oldDelegate.seed != seed || oldDelegate.count != count;
}

/// Plays a [ZadCelebrationBurst] over [child] whenever any value in [values]
/// goes up (e.g. tasks done or tasks handed in). Never on the first build.
class ZadCelebrateOnIncrease extends StatefulWidget {
  const ZadCelebrateOnIncrease({super.key, required this.values, required this.child});

  final List<int> values;
  final Widget child;

  @override
  State<ZadCelebrateOnIncrease> createState() => _ZadCelebrateOnIncreaseState();
}

class _ZadCelebrateOnIncreaseState extends State<ZadCelebrateOnIncrease> {
  int _bursts = 0;
  bool _showing = false;

  @override
  void didUpdateWidget(ZadCelebrateOnIncrease oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.values;
    final now = widget.values;
    var up = false;
    for (var i = 0; i < now.length && i < old.length; i++) {
      if (now[i] > old[i]) up = true;
    }
    if (up) {
      _bursts++;
      _showing = true;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_showing)
          Positioned.fill(
            child: ZadCelebrationBurst(
              key: ValueKey(_bursts),
              seed: _bursts,
              onDone: () {
                if (mounted) setState(() => _showing = false);
              },
            ),
          ),
      ]);
}
