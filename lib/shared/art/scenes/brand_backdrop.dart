import 'dart:math' as math;
import 'dart:ui';

import '../scene_palettes.dart';
import 'scene_common.dart';

/// Zad X brand backdrop (owner artwork 2026-11-27): deep navy with soft diagonal light bands,
/// a cool glow at the top and a warm glow at the bottom. Drawn in code (no image, no network),
/// so it is sharp on every screen and costs nothing in app size.
///
/// Used for the Zad X Play splash and the parent area (parent, settings, help, subscription).
/// Static: no motion. Only colours from [ScenePalettes.parentBrand] and soft glows are painted,
/// so loose text in [AppColors.onNavy] / [AppColors.onNavyMuted] stays readable (tested).
///
/// [ring]: a thin gold → sky ring around the middle with a small gold flare (splash only).
class BrandBackdropPainter extends CustomPainter {
  const BrandBackdropPainter({this.ring = false});

  final bool ring;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(r, vGradient(r, const [ArtColors.brandTop, ArtColors.brandMid, ArtColors.brandLow], const [0, 0.55, 1]));

    // Diagonal bands, rising from bottom-left to top-right, like the brand art.
    final d = size.width + size.height;
    final bands = [
      (0.18, 0.10, ArtColors.brandBand),
      (0.46, 0.16, ArtColors.brandBandSoft),
      (0.72, 0.07, ArtColors.brandBand),
      (0.92, 0.12, ArtColors.brandBandSoft),
    ];
    for (final (at, width, colour) in bands) {
      final x0 = d * at - size.height;
      final w = d * width * 0.5;
      final path = Path()
        ..moveTo(x0, size.height)
        ..lineTo(x0 + size.height, 0)
        ..lineTo(x0 + size.height + w, 0)
        ..lineTo(x0 + w, size.height)
        ..close();
      canvas.drawPath(path, fill(colour));
    }

    final u = sceneUnit(size);
    canvas.drawRect(r, glow(Offset(size.width * 0.9, size.height * 0.05), 320 * u, ArtColors.brandSkyGlow, 0.16));
    canvas.drawRect(r, glow(Offset(size.width * 0.05, size.height * 0.98), 280 * u, ArtColors.brandGoldGlow, 0.10));

    if (ring) {
      final c = Offset(size.width / 2, size.height / 2);
      final radius = math.min(size.width, size.height) * 0.42;
      final stroke = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * u
        ..shader = Gradient.sweep(c, [
          ArtColors.brandGoldGlow.withValues(alpha: 0.65),
          ArtColors.brandSkyGlow.withValues(alpha: 0.45),
          ArtColors.brandGoldGlow.withValues(alpha: 0.65),
        ]);
      canvas.drawCircle(c, radius, stroke);
      final flare = Offset(c.dx - radius, c.dy);
      canvas.drawCircle(flare, 26 * u, glow(flare, 26 * u, ArtColors.brandGoldGlow, 0.55));
    }
  }

  @override
  bool shouldRepaint(BrandBackdropPainter oldDelegate) => oldDelegate.ring != ring;
}
