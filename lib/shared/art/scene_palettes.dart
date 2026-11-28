import 'dart:math' as math;
import 'dart:ui';

/// Colour palette of one background scene.
///
/// Readability contract (tested in test/kids_art_test.dart): for scenes that
/// carry loose text (`textOnScene`), every colour in [contentColors], after
/// the [scrim] is laid over it, keeps WCAG 2.2 contrast ≥ 4.5:1 with the
/// app's muted body text (#5E5A78) and with ink. Painters only use colours
/// from their palette (white highlights and gold accents included), so the
/// scene can never sink below that line.
class ScenePalette {
  const ScenePalette({
    required this.contentColors,
    this.scrim = const Color(0x00000000),
    this.textOnScene = true,
    this.dark = false,
  });

  /// Every opaque colour the scene paints where content can scroll.
  final List<Color> contentColors;

  /// Soft veil painted between the scene and the content.
  final Color scrim;

  /// False for scenes that never carry loose text (night sky behind opaque
  /// cards, the decorative prayer-sky strip).
  final bool textOnScene;

  /// Dark scene (the Zad X brand navy): loose text uses the light colours
  /// `AppColors.onNavy` / `AppColors.onNavyMuted` instead of ink / muted, and the
  /// readability test checks those instead.
  final bool dark;
}

abstract final class ArtColors {
  // Shared pastels (high luminance, so muted text stays ≥ 4.5:1).
  static const white = Color(0xFFFFFFFF);
  static const sunGold = Color(0xFFFFD873);
  static const gold = Color(0xFFFFC83D);
  static const softGold = Color(0xFFFFE08A);
  static const windowGold = Color(0xFFFFE9A8);
  static const hillFar = Color(0xFFCDEFE0);
  static const hillNear = Color(0xFFB8E8D2);
  static const leaf = Color(0xFFA8E3C4);
  static const peach = Color(0xFFF7D9C4);
  static const lilac = Color(0xFFE9DDFB);
  static const lavender = Color(0xFFD9CCF7);
  static const iceBlue = Color(0xFFD7EEF9);
  static const scrimCream = Color(0x59FFF8F0); // cream at 35 %

  // Home sunrise sky.
  static const homeSkyTop = Color(0xFFDDF1FF);
  static const homeSkyMid = Color(0xFFFFF1E0);
  static const homeSkyLow = Color(0xFFFFE3C8);

  // Games.
  static const gamesSkyTop = Color(0xFFE3F2FF);
  static const gamesSkyMid = Color(0xFFF4EEFF);
  static const gamesSkyLow = Color(0xFFFBE9F5);
  static const islandGrass = Color(0xFFBFEBD6);
  static const islandEarth = Color(0xFFF6D9C2);
  static const islandPink = Color(0xFFFAD6E0);
  static const balloonSky = Color(0xFFBDEBFA);
  static const balloonLilac = Color(0xFFDCCCFF);
  static const balloonCoral = Color(0xFFFFC2C2);

  // Tasks garden.
  static const gardenSkyTop = Color(0xFFE6F7FF);
  static const gardenSkyLow = Color(0xFFEDFAF4);
  static const gardenBack = Color(0xFFCFF0DC);
  static const gardenFront = Color(0xFFBDE8CF);
  static const stem = Color(0xFF9ED9B5);
  static const flowerCentre = Color(0xFFFFD866);

  // Quran & Adhkar night.
  static const nightTop = Color(0xFF0E1A47);
  static const nightMid = Color(0xFF1B2560);
  static const nightLow = Color(0xFF2B2A6E);
  static const nightSkyline = Color(0xFF0B1540);
  static const moonGlow = Color(0xFFFFE7A3);

  // Zad X brand navy backdrop (owner artwork 2026-11-27). Bands are the backdrop with a faint
  // white veil already blended in (opaque, so the contrast test can check them).
  static const brandTop = Color(0xFF0A225E);
  static const brandMid = Color(0xFF0B1B4C);
  static const brandLow = Color(0xFF081338);
  static const brandBand = Color(0xFF162C66);
  static const brandBandSoft = Color(0xFF112458);
  static const brandSkyGlow = Color(0xFF4CC9F0);
  static const brandGoldGlow = Color(0xFFFFC83D);

  // Parent area.
  static const parentBg = Color(0xFFF5F8FF);
  static const parentLine = Color(0xFFDCE5F7);
  static const parentLineSoft = Color(0xFFE6ECFA);
}

abstract final class ScenePalettes {
  static const home = ScenePalette(
    scrim: ArtColors.scrimCream,
    contentColors: [
      ArtColors.homeSkyTop, ArtColors.homeSkyMid, ArtColors.homeSkyLow, ArtColors.sunGold, ArtColors.white,
      ArtColors.hillFar, ArtColors.hillNear, ArtColors.peach, ArtColors.lilac, ArtColors.iceBlue,
      ArtColors.windowGold, ArtColors.lavender, ArtColors.gold, ArtColors.leaf,
    ],
  );

  static const games = ScenePalette(
    scrim: ArtColors.scrimCream,
    contentColors: [
      ArtColors.gamesSkyTop, ArtColors.gamesSkyMid, ArtColors.gamesSkyLow, ArtColors.islandGrass, ArtColors.leaf,
      ArtColors.islandEarth, ArtColors.islandPink, ArtColors.softGold, ArtColors.gold, ArtColors.balloonSky,
      ArtColors.balloonLilac, ArtColors.balloonCoral, ArtColors.white,
    ],
  );

  static const tasks = ScenePalette(
    scrim: ArtColors.scrimCream,
    contentColors: [
      ArtColors.gardenSkyTop, ArtColors.gardenSkyLow, ArtColors.gardenBack, ArtColors.gardenFront, ArtColors.stem,
      ArtColors.balloonCoral, ArtColors.softGold, ArtColors.balloonLilac, ArtColors.balloonSky,
      ArtColors.flowerCentre, ArtColors.sunGold, ArtColors.islandEarth, ArtColors.white,
    ],
  );

  /// Night sky: only opaque cards sit on it, never loose text.
  static const quran = ScenePalette(
    textOnScene: false,
    contentColors: [ArtColors.nightTop, ArtColors.nightMid, ArtColors.nightLow, ArtColors.nightSkyline],
  );

  /// Decorative strip, never carries text.
  static const prayer = ScenePalette(textOnScene: false, contentColors: []);

  /// Zad X Kids parent area: light pattern.
  static const parent = ScenePalette(
    contentColors: [ArtColors.parentBg, ArtColors.parentLine, ArtColors.parentLineSoft, ArtColors.white],
  );

  /// Zad X Play parent area (owner decision 2026-11-27): the brand navy backdrop. The colours
  /// include the strongest points of the sky and gold glows over a band.
  static const parentBrand = ScenePalette(
    dark: true,
    contentColors: [
      ArtColors.brandTop, ArtColors.brandMid, ArtColors.brandLow, ArtColors.brandBand, ArtColors.brandBandSoft,
      Color(0xFF1F457C), // brandBand + 16 % sky glow (strongest point)
      Color(0xFF2D3C62), // brandBand + 10 % gold glow (strongest point)
    ],
  );
}

/// WCAG helpers (also used by the tests).
abstract final class Contrast {
  static double _channel(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double luminance(Color c) => 0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// [top] (with its alpha) painted over opaque [bottom], as Flutter blends it.
  static Color over(Color top, Color bottom) {
    final a = top.a;
    return Color.from(
      alpha: 1,
      red: top.r * a + bottom.r * (1 - a),
      green: top.g * a + bottom.g * (1 - a),
      blue: top.b * a + bottom.b * (1 - a),
    );
  }
}
