import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Sky moods that follow the prayer day.
enum PrayerSkyPhase { dawn, day, afternoon, sunset, night }

/// Picks the sky for [now] (local clock hours, e.g. 15.5 = 15:30) from the
/// day's prayer times. Missing times (NaN at extreme latitudes) fall back to
/// typical clock hours so the sky is always sensible.
PrayerSkyPhase prayerSkyPhaseFor({
  required double now,
  required double fajr,
  required double dhuhr,
  required double asr,
  required double maghrib,
  required double isha,
}) {
  double ok(double v, double fallback) => v.isFinite ? v : fallback;
  final f = ok(fajr, 5);
  final d = ok(dhuhr, 12);
  final a = ok(asr, 15.5);
  final m = ok(maghrib, 18);
  final i = ok(isha, m + 1.5);
  if (now < f || now >= i) return PrayerSkyPhase.night;
  if (now < d) return now < math.min(f + 1.5, d) ? PrayerSkyPhase.dawn : PrayerSkyPhase.day;
  if (now < a) return PrayerSkyPhase.day;
  if (now < m - 0.5) return PrayerSkyPhase.afternoon;
  return PrayerSkyPhase.sunset;
}

class PrayerSkyStyle {
  const PrayerSkyStyle(this.sky, this.hill, this.sunAt, this.sunColor, {this.moon = false, this.stars = 0, this.clouds = true});
  final List<Color> sky;
  final Color hill;
  final Offset sunAt; // fractions of the size
  final Color sunColor;
  final bool moon;
  final int stars;
  final bool clouds;

  static const of = {
    PrayerSkyPhase.dawn: PrayerSkyStyle(
      [Color(0xFF2B3A7A), Color(0xFF8E7CC3), Color(0xFFFFB8A0)],
      Color(0xFF5B5E9E),
      Offset(0.78, 0.92),
      Color(0xFFFFD873),
      stars: 6,
      clouds: false,
    ),
    PrayerSkyPhase.day: PrayerSkyStyle(
      [Color(0xFF7FD3F7), Color(0xFFBFE9FB)],
      Color(0xFF8FDDB5),
      Offset(0.5, 0.28),
      Color(0xFFFFD873),
    ),
    PrayerSkyPhase.afternoon: PrayerSkyStyle(
      [Color(0xFF9FD8F2), Color(0xFFFFE7B0)],
      Color(0xFF9CD9A8),
      Offset(0.28, 0.45),
      Color(0xFFFFC83D),
    ),
    PrayerSkyPhase.sunset: PrayerSkyStyle(
      [Color(0xFF5B4B9A), Color(0xFFFF8C6B), Color(0xFFFFC98A)],
      Color(0xFF4E3F7E),
      Offset(0.2, 0.86),
      Color(0xFFFFB347),
    ),
    PrayerSkyPhase.night: PrayerSkyStyle(
      [Color(0xFF0A225E), Color(0xFF1B2560)],
      Color(0xFF0B1540),
      Offset(0.8, 0.32),
      ArtColors.moonGlow,
      moon: true,
      stars: 14,
      clouds: false,
    ),
  };
}

class PrayerSkyStaticPainter extends CustomPainter {
  const PrayerSkyStaticPainter(this.phase);
  final PrayerSkyPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final s = PrayerSkyStyle.of[phase]!;
    final rect = Offset.zero & size;
    final u = math.max(0.6, math.min(size.height / 80, 1.4));
    canvas.drawRect(rect, vGradient(rect, s.sky));
    final c = Offset(size.width * s.sunAt.dx, size.height * s.sunAt.dy);
    canvas.drawCircle(c, 50 * u, glow(c, 50 * u, s.sunColor, 0.45));
    if (s.moon) {
      canvas.drawPath(ArtShapes.crescent(c, 13 * u), fill(s.sunColor));
    } else {
      canvas.drawCircle(c, 15 * u, fill(s.sunColor));
    }
    canvas.drawPath(ArtShapes.hill(size, size.height - 14 * u, amp: 5 * u, waves: 1.3), fill(s.hill));
    // A small dome on the hill.
    final dx = size.width * 0.62;
    final base = size.height - 14 * u;
    canvas.drawRect(Rect.fromLTWH(dx - 14 * u, base - 10 * u, 28 * u, 24 * u), fill(s.hill));
    canvas.drawPath(ArtShapes.dome(Offset(dx - 11 * u, base - 9 * u), 22 * u, base - 30 * u), fill(s.hill));
  }

  @override
  bool shouldRepaint(PrayerSkyStaticPainter oldDelegate) => oldDelegate.phase != phase;
}

class PrayerSkyMotionPainter extends CustomPainter {
  PrayerSkyMotionPainter(this.t, this.phase) : super(repaint: t);
  final Animation<double> t;
  final PrayerSkyPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final s = PrayerSkyStyle.of[phase]!;
    final v = t.value;
    final u = math.max(0.6, math.min(size.height / 80, 1.4));
    final r = math.Random(5);
    for (var i = 0; i < s.stars; i++) {
      final p = Offset(r.nextDouble() * size.width, r.nextDouble() * size.height * 0.6);
      final a = 0.55 + 0.3 * Loop.wave(v, 2 + i % 2, r.nextDouble());
      canvas.drawPath(ArtShapes.sparkle(p, 3.5 * u), fill(ArtColors.white, a));
    }
    if (s.clouds) {
      for (final (yf, cw, start) in const [(0.32, 60.0, 0.1), (0.55, 44.0, 0.6)]) {
        final w = cw * u;
        final x = Loop.drift(v, 1, start) * (size.width + 2 * w) - w;
        canvas.drawPath(ArtShapes.cloud(Offset(x, size.height * yf), w), fill(ArtColors.white, 0.8));
      }
    }
  }

  @override
  bool shouldRepaint(PrayerSkyMotionPainter oldDelegate) => oldDelegate.t != t || oldDelegate.phase != phase;
}
