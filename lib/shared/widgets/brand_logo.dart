import 'package:flutter/material.dart';

import '../../core/app_variant.dart';
import '../../core/theme/app_colors.dart';

/// The Zad X logo of this build. Use it everywhere a logo is shown (header, splash, about…).
///
/// * Zad X Play: the artwork logo ([islamicAsset]).
/// * Zad X Kids: a drawn "Zad X Kids" Latin wordmark in the Kids palette (teal, sun yellow,
///   coral). The artwork logo has Arabic lettering, a crescent, mosques and the line "with
///   Islamic Values", so it must never appear in Kids. TODO(owner): a neutral Kids artwork logo +
///   launcher icon (docs/decisions/ZADX-KIDS-VARIANT.md).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 150, this.height = 99, this.variant = appVariant});

  /// Zad X Play only. Removed from the Kids bundle by tools/kids_variant_prepare.py.
  static const islamicAsset = 'assets/images/zadx_logo.jpg';

  final double width;
  final double height;

  /// Which app's logo (default: this build). The Kids build always draws the Kids wordmark,
  /// whatever is passed (`kIsKids` is a compile-time constant, so the artwork logo is tree-shaken).
  final AppVariant variant;

  /// True when this widget shows the Zad X Play artwork logo.
  bool get showsArtwork => !kIsKids && variant == AppVariant.islamic;

  @override
  Widget build(BuildContext context) {
    if (!kIsKids && variant == AppVariant.islamic) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          islamicAsset,
          width: width,
          height: height,
          fit: BoxFit.cover,
          semanticLabel: 'Zad X',
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
        ),
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
