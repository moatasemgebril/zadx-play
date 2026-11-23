import 'package:flutter/widgets.dart';

import '../art_shapes.dart';
import '../scene_palettes.dart';
import 'scene_common.dart';

/// Parent area (and settings, help, subscription): clean, light geometric
/// pattern only. Professional, no motion.
///
/// * Zad X Play: a faint eight-point-star lattice.
/// * Zad X Kids ([religiousMotifs] false): a neutral grid of soft rounded squares and dots.
class ParentStaticPainter extends CustomPainter {
  const ParentStaticPainter({this.religiousMotifs = artReligiousMotifs});

  final bool religiousMotifs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, fill(ArtColors.parentBg));
    final u = sceneUnit(size);
    final step = 64 * u;
    if (!religiousMotifs) {
      final square = Paint()
        ..color = ArtColors.parentLine
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * u;
      final dot = Paint()..color = ArtColors.parentLine;
      for (var y = 0.0; y < size.height + step; y += step) {
        for (var x = 0.0; x < size.width + step; x += step) {
          final c = Offset(x, y);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(center: c, width: step * 0.3, height: step * 0.3),
              Radius.circular(step * 0.09),
            ),
            square,
          );
          canvas.drawCircle(c + Offset(step / 2, step / 2), 2.4 * u, dot);
        }
      }
      return;
    }
    final star = Paint()
      ..color = ArtColors.parentLine
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2 * u;
    final link = Paint()
      ..color = ArtColors.parentLineSoft
      ..strokeWidth = 1 * u;
    for (var y = 0.0; y < size.height + step; y += step) {
      for (var x = 0.0; x < size.width + step; x += step) {
        final c = Offset(x, y);
        canvas.drawPath(ArtShapes.eightPointStar(c, step * 0.22), star);
        canvas.drawLine(c + Offset(step * 0.22, 0), c + Offset(step * 0.78, 0), link);
        canvas.drawLine(c + Offset(0, step * 0.22), c + Offset(0, step * 0.78), link);
      }
    }
  }

  @override
  bool shouldRepaint(ParentStaticPainter oldDelegate) => oldDelegate.religiousMotifs != religiousMotifs;
}
