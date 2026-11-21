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

/// The adhan voice. Owner decision 2026-11-21: one adhan only, from the
/// Prophet's Mosque in Madinah, with no chooser. Attribution required by its
/// CC BY 3.0 licence is shown in the parent area (Credits card) and in
/// assets/audio/ADHAN-CREDITS.txt.
const muezzins = <Voice>[
  Voice(id: 'madinah_rec', name: Localized('أذان المسجد النبوي', "Adhan from the Prophet's Mosque"), source: 'assets/audio/adhan_madinah_rec.mp3', licenceConfirmed: true,
      credit: 'ejaz215 · CC BY 3.0 · Freesound / Wikimedia Commons'),
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
