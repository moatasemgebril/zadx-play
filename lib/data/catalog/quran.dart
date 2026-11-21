import 'package:flutter/foundation.dart';

import '../../core/localized.dart';
import '../models/surah.dart';

/// Adhan phrases shown while the adhan plays.
const adhanPhrases = <String>[
  'اللهُ أكبرُ، اللهُ أكبرُ',
  'اللهُ أكبرُ، اللهُ أكبرُ',
  'أشهدُ أن لا إله إلا الله',
  'أشهدُ أن لا إله إلا الله',
  'أشهدُ أنّ محمدًا رسولُ الله',
  'أشهدُ أنّ محمدًا رسولُ الله',
  'حيَّ على الصلاة',
  'حيَّ على الصلاة',
  'حيَّ على الفلاح',
  'حيَّ على الفلاح',
  'اللهُ أكبرُ، اللهُ أكبرُ',
  'لا إله إلا الله',
];

/// Adhan voices. Only voices with `licenceConfirmed: true` AND a bundled file are
/// offered (see [availableMuezzins]); the others stay hidden until a licensed
/// recording is added to assets/audio/.
const muezzins = <Voice>[
  // Freely-licensed recordings from Wikimedia Commons (see assets/audio/ADHAN-CREDITS.txt).
  Voice(id: 'zadx', name: Localized('أذان زاد ١', 'Zad X adhan 1'), source: 'assets/audio/adhan_zadx.mp3', licenceConfirmed: true),
  Voice(id: 'aaqib', name: Localized('عاقب عزيز', 'Aaqib Azeez'), source: 'assets/audio/adhan_aaqib.mp3', licenceConfirmed: true,
      credit: 'Atcovi · CC BY-SA 4.0 · Wikimedia Commons'),
  Voice(id: 'andrewler', name: Localized('أذان زاد ٢', 'Zad X adhan 2'), source: 'assets/audio/adhan_andrewler.mp3', licenceConfirmed: true,
      credit: 'Andrewler · CC BY-SA 4.0 · Wikimedia Commons'),
  Voice(id: 'madinah_rec', name: Localized('من المسجد النبوي', 'From the Prophet\'s Mosque'), source: 'assets/audio/adhan_madinah_rec.mp3', licenceConfirmed: true,
      credit: 'ejaz215 · CC BY 3.0 · Freesound / Wikimedia Commons'),
  Voice(id: 'makkah', name: Localized('أذان مكة', 'Makkah adhan'), source: 'assets/audio/adhan_makkah.mp3'),
  Voice(id: 'madinah', name: Localized('أذان المدينة', 'Madinah adhan'), source: 'assets/audio/adhan_madinah.mp3'),
  Voice(id: 'refaat', name: Localized('محمد رفعت', 'Muhammad Refaat'), source: 'assets/audio/adhan_refaat.mp3'),
  Voice(id: 'afasy', name: Localized('مشاري العفاسي', 'Mishary Alafasy'), source: 'assets/audio/adhan_afasy.mp3'),
];

/// The adhan voices a screen may offer: licensed ones with a bundled file.
List<Voice> availableMuezzins({List<Voice> all = muezzins}) =>
    all.where((m) => m.licenceConfirmed).toList();

/// The adhan voice to play for the saved [id]: that voice if available, else the first.
Voice resolveMuezzin(String? id, {List<Voice>? available}) {
  final list = available ?? availableMuezzins();
  return list.where((m) => m.id == id).firstOrNull ?? list.first;
}

/// Reciters. [source] is the EveryAyah folder name.
///
/// LICENCE: set `licenceConfirmed: true` on a reciter ONLY after written
/// permission is on file. 2026-11-21: Quran Foundation approved these four
/// (all Hafs) in writing for our paid kids' app, delivered via the QF
/// recitations APIs (see BACKLOG.md "Quran Foundation approval").
/// PRE-LAUNCH BLOCKER: the approval covers QF's APIs, not EveryAyah URLs, so
/// the audio source must move to the QF recitations API (no rehosting; device
/// download allowed) before a store release. Abdur-Rashid Sufi is NOT approved
/// and must not be added. See docs/STORE_CHECKLIST.md.
const reciters = <Voice>[
  Voice(id: 'afasy', name: Localized('مشاري العفاسي', 'Mishary Alafasy'), source: 'Alafasy_128kbps', licenceConfirmed: true),
  Voice(id: 'basit', name: Localized('عبد الباسط عبد الصمد', 'Abdul Basit'), source: 'Abdul_Basit_Murattal_192kbps', licenceConfirmed: true),
  Voice(id: 'husary', name: Localized('محمود خليل الحصري', 'Al-Husary'), source: 'Husary_128kbps', licenceConfirmed: true),
  Voice(id: 'minshawi', name: Localized('محمد صديق المنشاوي', 'Al-Minshawi'), source: 'Minshawy_Murattal_128kbps', licenceConfirmed: true),
];

/// Reciters a screen may offer.
///
/// Release builds return only reciters whose licence is confirmed in writing,
/// for everyone (streaming unlicensed audio from a store build is the risk we
/// avoid). Debug builds return all reciters so parents/testers can try them;
/// the UI must label the unconfirmed ones "licence pending"
/// (see [Voice.licenceConfirmed]).
List<Voice> visibleReciters({bool releaseBuild = kReleaseMode, List<Voice> all = reciters}) =>
    releaseBuild ? all.where((r) => r.licenceConfirmed).toList() : List<Voice>.of(all);

/// The reciter to play for the saved [id]: that reciter if visible, else the
/// first visible one, else null (no recitation available). Never throws.
Voice? resolveReciter(String? id, List<Voice> visible) {
  if (visible.isEmpty) return null;
  return visible.where((v) => v.id == id).firstOrNull ?? visible.first;
}
