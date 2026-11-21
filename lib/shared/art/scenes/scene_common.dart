import 'dart:math' as math;
import 'dart:ui';

/// Scale unit so the scenes look the same on a 360 dp phone and a tablet.
double sceneUnit(Size s) => (math.min(s.width / 360, s.height / 640)).clamp(0.75, 1.6).toDouble();

Paint fill(Color c, [double alpha = 1]) => Paint()
  ..isAntiAlias = true
  ..color = alpha >= 1 ? c : c.withValues(alpha: c.a * alpha);

/// Vertical gradient. With more than two colours and no [stops], the colours
/// are spread evenly (dart:ui requires stops for 3+ colours).
Paint vGradient(Rect r, List<Color> colors, [List<double>? stops]) => Paint()
  ..shader = Gradient.linear(
    r.topCenter,
    r.bottomCenter,
    colors,
    stops ?? (colors.length > 2 ? [for (var i = 0; i < colors.length; i++) i / (colors.length - 1)] : null),
  );

Paint glow(Offset c, double r, Color color, double alpha) => Paint()
  ..shader = Gradient.radial(c, r, [color.withValues(alpha: alpha), color.withValues(alpha: 0)]);
