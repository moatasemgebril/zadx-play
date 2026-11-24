import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_variant.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'brand_logo.dart';

/// White rounded card with the soft purple shadow used across Zad X.
class ZadCard extends StatelessWidget {
  const ZadCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.border});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: border,
          boxShadow: const [BoxShadow(color: Color(0x1A6C3BEB), blurRadius: 18, offset: Offset(0, 6))],
        ),
        child: child,
      );
}

class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key, this.subtitle});
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: AppTheme.display(28)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: const TextStyle(fontSize: 16, color: AppColors.muted)),
            ),
        ],
      );
}

/// Status banner (lock reason, games open, alerts).
class Banner2 extends StatelessWidget {
  const Banner2({super.key, required this.text, required this.bg, required this.fg, this.icon});
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: fg, size: 22), const SizedBox(width: 8)],
          Expanded(child: Text(text, style: TextStyle(color: fg, fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
      );
}

/// Grid of selectable chips (country, city, method, muezzin...).
class ChoiceGrid<T> extends StatelessWidget {
  const ChoiceGrid({
    super.key,
    required this.items,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.columns = 3,
    this.disabled,
    this.note,
  });

  final List<T> items;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final int columns;
  final bool Function(T)? disabled;
  final String? Function(T)? note;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 6.0;
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final item in items)
            SizedBox(
              width: w,
              child: _Chip(
                text: label(item),
                note: note?.call(item),
                selected: item == selected,
                enabled: !(disabled?.call(item) ?? false),
                onTap: () => onSelected(item),
              ),
            ),
        ],
      );
    });
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.selected, required this.enabled, required this.onTap, this.note});
  final String text;
  final String? note;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = !enabled ? Colors.white : (selected ? AppColors.purple : AppColors.purpleSoft);
    final fg = !enabled ? AppColors.muted : (selected ? Colors.white : AppColors.ink);
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: enabled ? BorderSide.none : const BorderSide(color: Color(0xFFC9C2E6)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: fg, fontSize: 16, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                if (note != null) Text(note!, style: TextStyle(color: fg, fontSize: 12)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, required this.color, this.height = 10, this.track = AppColors.purpleSoft});
  final double value;
  final Color color;
  final double height;
  final Color track;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: height,
          color: color,
          backgroundColor: track,
        ),
      );
}

/// Playful background: soft tint + scattered stars/circles + faint Zad X logo.
class PatternBackground extends StatelessWidget {
  const PatternBackground({super.key, required this.tint, required this.child, this.seed = 7});
  final Color tint;
  final Widget child;
  final int seed;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Positioned.fill(child: ColoredBox(color: tint)),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _PatternPainter(seed)))),
        // Logo watermark. Zad X Kids has no artwork logo yet (the Zad X Play logo shows a crescent
        // and mosques), so it gets no watermark: docs/decisions/ZADX-KIDS-VARIANT.md.
        if (!kIsKids)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.12,
                  child: ShaderMask(
                    shaderCallback: (r) => const RadialGradient(colors: [Colors.black, Colors.transparent], stops: [0.45, 0.75])
                        .createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: Transform.rotate(
                      angle: -0.1,
                      child: Image.asset(BrandLogo.islamicAsset, width: 340, excludeFromSemantics: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        child,
      ]);
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.seed);
  final int seed;

  static const _colors = [AppColors.purple, AppColors.yellow, AppColors.coral, AppColors.sky, AppColors.mint];

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed);
    const cols = 4, rows = 9;
    final cw = size.width / cols, ch = size.height / rows;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final paint = Paint()..color = _colors[(x + y) % _colors.length].withValues(alpha: 0.18);
        final c = Offset(x * cw + r.nextDouble() * cw, y * ch + r.nextDouble() * ch);
        final s = 8 + r.nextDouble() * 10;
        if ((x + y).isEven) {
          canvas.drawPath(_star(c, s), paint);
        } else {
          canvas.drawCircle(c, s * 0.6, paint);
        }
      }
    }
  }

  Path _star(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  @override
  bool shouldRepaint(_PatternPainter old) => old.seed != seed;
}

void showToast(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.mintText,
    ));
}
