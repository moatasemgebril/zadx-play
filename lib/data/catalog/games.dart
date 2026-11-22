import 'package:flutter/material.dart';

import '../../core/app_variant.dart';
import '../../core/localized.dart';
import '../models/game.dart';

/// The 15 most popular kids games (2026 download charts).
///
/// TODO(release): verify every Android package name on Google Play before
/// shipping; publishers occasionally change them. Icons are our own
/// Material icons — never ship the publishers' logos without permission.
const controlledGames = <ControlledGame>[
  ControlledGame(id: 'roblox', name: 'Roblox', tag: Localized('عوالم ومغامرات', 'Worlds & adventures'), icon: Icons.view_in_ar_rounded, bg: Color(0xFFE6F7FD), fg: Color(0xFF0B87B3), androidPackage: 'com.roblox.client', iosUrlScheme: 'roblox://'),
  ControlledGame(id: 'minecraft', name: 'Minecraft', tag: Localized('بناء واستكشاف', 'Build & explore'), icon: Icons.landscape_rounded, bg: Color(0xFFE3F7EA), fg: Color(0xFF1F7A4D), androidPackage: 'com.mojang.minecraftpe', iosUrlScheme: 'minecraft://'),
  ControlledGame(id: 'fortnite', name: 'Fortnite', tag: Localized('باتل رويال', 'Battle royale'), icon: Icons.paragliding_rounded, bg: Color(0xFFF1E9FF), fg: Color(0xFF6C3BEB), androidPackage: 'com.epicgames.fortnite', olderKids: true),
  ControlledGame(id: 'brawlstars', name: 'Brawl Stars', tag: Localized('معارك جماعية', 'Team battles'), icon: Icons.star_rounded, bg: Color(0xFFFFF4D6), fg: Color(0xFF8A5A00), androidPackage: 'com.supercell.brawlstars'),
  ControlledGame(id: 'subway', name: 'Subway Surfers', tag: Localized('جري وتحدي', 'Endless runner'), icon: Icons.bolt_rounded, bg: Color(0xFFFFE9D6), fg: Color(0xFFC2410C), androidPackage: 'com.kiloo.subwaysurf'),
  ControlledGame(id: 'stumble', name: 'Stumble Guys', tag: Localized('سباقات مضحكة', 'Party races'), icon: Icons.emoji_events_rounded, bg: Color(0xFFFFF4D6), fg: Color(0xFF8A5A00), androidPackage: 'com.kitkagames.fallbuddies'),
  ControlledGame(id: 'clashroyale', name: 'Clash Royale', tag: Localized('استراتيجية وكروت', 'Cards & strategy'), icon: Icons.workspace_premium_rounded, bg: Color(0xFFE6EEFF), fg: Color(0xFF1D4ED8), androidPackage: 'com.supercell.clashroyale'),
  ControlledGame(id: 'amongus', name: 'Among Us', tag: Localized('لعب جماعي وألغاز', 'Social mystery'), icon: Icons.rocket_launch_rounded, bg: Color(0xFFFFE4E1), fg: Color(0xFFC2263E), androidPackage: 'com.innersloth.spacemafia'),
  ControlledGame(id: 'blockblast', name: 'Block Blast!', tag: Localized('ألغاز مكعبات', 'Block puzzle'), icon: Icons.grid_view_rounded, bg: Color(0xFFF1E9FF), fg: Color(0xFF6C3BEB), androidPackage: 'com.block.juggle'),
  ControlledGame(id: 'candycrush', name: 'Candy Crush Saga', tag: Localized('ألغاز وتوصيل', 'Match-3 puzzle'), icon: Icons.icecream_rounded, bg: Color(0xFFFFE4F1), fg: Color(0xFFBE185D), androidPackage: 'com.king.candycrushsaga'),
  ControlledGame(id: 'fcmobile', name: 'EA SPORTS FC Mobile', tag: Localized('كرة قدم', 'Football'), icon: Icons.sports_soccer_rounded, bg: Color(0xFFE3F7EA), fg: Color(0xFF15803D), androidPackage: 'com.ea.gp.fifamobile'),
  ControlledGame(id: 'freefire', name: 'Free Fire', tag: Localized('باتل رويال', 'Battle royale'), icon: Icons.gps_fixed_rounded, bg: Color(0xFFFFE9D6), fg: Color(0xFFC2410C), androidPackage: 'com.dts.freefireth', olderKids: true),
  ControlledGame(id: 'pubg', name: 'PUBG MOBILE', tag: Localized('باتل رويال', 'Battle royale'), icon: Icons.track_changes_rounded, bg: Color(0xFFEEF0F4), fg: Color(0xFF374151), androidPackage: 'com.tencent.ig', olderKids: true),
  ControlledGame(id: 'tocaboca', name: 'Toca Boca World', tag: Localized('تخيّل ولعب أدوار', 'Pretend play'), icon: Icons.house_rounded, bg: Color(0xFFFFE4F1), fg: Color(0xFFBE185D), androidPackage: 'com.tocaboca.tocalifeworld'),
  ControlledGame(id: 'ludoking', name: 'Ludo King', tag: Localized('لودو مع العيلة', 'Ludo with the family'), icon: Icons.casino_rounded, bg: Color(0xFFE6EEFF), fg: Color(0xFF1D4ED8), androidPackage: 'com.ludo.king'),
];

/// Built-in learning games (always unlocked).
class ZadGame {
  const ZadGame(this.id, this.icon, this.bg, this.fg);
  final String id;
  final IconData icon;
  final Color bg;
  final Color fg;
}

const zadGames = <ZadGame>[
  ZadGame('letters', Icons.abc_rounded, Color(0xFFFFC83D), Color(0xFF1F1A3D)),
  ZadGame('prophets', Icons.auto_awesome_rounded, Color(0xFF4CC9F0), Color(0xFF1F1A3D)),
  ZadGame('masjid', Icons.mosque_rounded, Color(0xFF7ED9B8), Color(0xFF1F1A3D)),
];

/// Learning games of Zad X Play only (prophets quiz, mosque builder).
const islamicOnlyZadGameIds = {'prophets', 'masjid'};

/// Learning games that are not in Zad X Kids: the Islamic ones and the Arabic Letters game
/// (Arabic-language content; Zad X Kids targets the US / Europe, owner decision 2026-11-22).
const playOnlyZadGameIds = {...islamicOnlyZadGameIds, 'letters'};

/// Built-in games of [variant]. Zad X Kids has none for now (the Games tab hides the section);
/// a neutral learning game can be added here later.
List<ZadGame> zadGamesFor(AppVariant variant) =>
    variant == AppVariant.kids ? [for (final g in zadGames) if (!playOnlyZadGameIds.contains(g.id)) g] : zadGames;

/// Built-in games of this build.
final List<ZadGame> activeZadGames = zadGamesFor(appVariant);
