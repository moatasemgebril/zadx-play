import 'package:flutter/material.dart';

import '../../core/app_variant.dart';
import '../../core/theme/app_colors.dart';

/// The Zad X logo of this build. Use it everywhere a logo is shown (header, splash, about…).
///
/// * Zad X Play (owner decision 2026-11-27): the "ZX ZAD X" wordmark ([wordmarkAsset]) on a navy
///   plate, or with [emblem] just the "ZX" mark ([emblemAsset], transparent, for the splash).
///   Both are cut from the owner's artwork by tools/gen_brand_assets.py.
/// * Zad X Kids: a drawn "Zad X Kids" Latin wordmark in the Kids palette (teal, sun yellow,
///   coral). The phone icon is the shared "ZX" (owner decision 2026-11-27); the Kids bundle has
///   no logo image (tools/kids_variant_prepare.py removes them).
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.width = 168,
    this.height = 68,
    this.variant = appVariant,
    this.emblem = false,
  });

  /// Zad X Play only. Removed from the Kids bundle by tools/kids_variant_prepare.py.
  static const wordmarkAsset = 'assets/images/zadx_wordmark.webp';

  /// Zad X Play only ("ZX" without the words). Removed from the Kids bundle too.
  static const emblemAsset = 'assets/images/zadx_emblem.webp';

  final double width;
  final double height;

  /// Which app's logo (default: this build). The Kids build always draws the Kids wordmark,
  /// whatever is passed (`kIsKids` is a compile-time constant, so the artwork is tree-shaken).
  final AppVariant variant;

  /// Zad X Play: show only the "ZX" mark (transparent) instead of the wordmark plate.
  final bool emblem;

  /// True when this widget shows Zad X Play artwork.
  bool get showsArtwork => !kIsKids && variant == AppVariant.islamic;

  @override
  Widget build(BuildContext context) {
    if (!kIsKids && variant == AppVariant.islamic) {
      final image = Image.asset(
        emblem ? emblemAsset : wordmarkAsset,
        width: width,
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'Zad X',
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
      );
      if (emblem) return image;
      // The wordmark's soft glow is cut for navy: always show it on the brand navy plate,
      // so it looks the same on the navy header and inside white cards.
      return DecoratedBox(
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
        child: image,
      );
    }
    return const KidsWordmark().sized(width, height);
  }
}

/// "Zad X Kids" drawn with Latin text only (no artwork, no religious symbol, no Arabic script).
/// Uses the platform's bundled font (heavy weight): nothing is downloaded, so it also works on
/// the launch splash before anything else has loaded.
class KidsWordmark extends StatelessWidget {
  const KidsWordmark({super.key});

  /// Every visible letter of the wordmark (tested: Latin only).
  static const words = ['ZAD', 'X', 'KIDS'];

  static TextStyle _style(double size, Color color, {double spacing = 0.5}) =>
      TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color, height: 1.1, letterSpacing: spacing);

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Zad X Kids',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [KidsColors.teal, KidsColors.tealDeep],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: FittedBox(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text('${words[0]} ', style: _style(30, Colors.white)),
                  Text(words[1], style: _style(36, KidsColors.sun)),
                ]),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                  decoration: BoxDecoration(color: KidsColors.coral, borderRadius: BorderRadius.circular(999)),
                  child: Text(words[2], style: _style(15, AppColors.ink, spacing: 3)),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget sized(double width, double height) => SizedBox(width: width, height: height, child: this);
}
