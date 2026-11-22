import 'package:flutter/material.dart';

import '../../core/app_variant.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// The Zad X logo of this build. Use it everywhere a logo is shown (header, splash, about…).
///
/// * Zad X Play: the artwork logo ([islamicAsset]).
/// * Zad X Kids: a drawn "Zad X Kids" wordmark. The artwork logo has a crescent, mosques and the
///   line "with Islamic Values", so it must never appear in Kids. TODO(owner): a neutral Kids
///   artwork logo + launcher icon (docs/decisions/ZADX-KIDS-VARIANT.md).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.width = 150, this.height = 99});

  /// Zad X Play only. Removed from the Kids bundle by tools/kids_variant_prepare.py.
  static const islamicAsset = 'assets/images/zadx_logo.jpg';

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (!kIsKids) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(islamicAsset, width: width, height: height, fit: BoxFit.cover, semanticLabel: 'Zad X'),
      );
    }
    return const KidsWordmark().sized(width, height);
  }
}

/// "Zad X Kids" drawn with text only (no artwork, no religious symbols).
class KidsWordmark extends StatelessWidget {
  const KidsWordmark({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Zad X Kids',
        excludeSemantics: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.purple, AppColors.purpleDark]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: FittedBox(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('ZAD ', style: AppTheme.display(30, color: Colors.white)),
                  Text('X', style: AppTheme.display(34, color: AppColors.yellow)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                decoration: BoxDecoration(color: AppColors.yellow, borderRadius: BorderRadius.circular(999)),
                child: Text('KIDS', style: AppTheme.display(16, color: AppColors.ink)),
              ),
            ]),
          ),
        ),
      );

  Widget sized(double width, double height) => SizedBox(width: width, height: height, child: this);
}
