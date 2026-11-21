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

const muezzins = <Voice>[
  Voice(id: 'makkah', name: Localized('أذان مكة', 'Makkah adhan'), source: 'assets/audio/adhan_makkah.mp3'),
  Voice(id: 'madinah', name: Localized('أذان المدينة', 'Madinah adhan'), source: 'assets/audio/adhan_madinah.mp3'),
  Voice(id: 'refaat', name: Localized('محمد رفعت', 'Muhammad Refaat'), source: 'assets/audio/adhan_refaat.mp3'),
  Voice(id: 'afasy', name: Localized('مشاري العفاسي', 'Mishary Alafasy'), source: 'assets/audio/adhan_afasy.mp3'),
];

/// Reciters. [source] is the EveryAyah folder name.
///
/// LICENCE: set `licenceConfirmed: true` on a reciter ONLY after written
/// permission is on file. Today none is confirmed, so release builds show no
/// recitation (the Quran text still works). Pre-launch blocker, see
/// docs/STORE_CHECKLIST.md.
const reciters = <Voice>[
  Voice(id: 'afasy', name: Localized('مشاري العفاسي', 'Mishary Alafasy'), source: 'Alafasy_128kbps'),
  Voice(id: 'basit', name: Localized('عبد الباسط عبد الصمد', 'Abdul Basit'), source: 'Abdul_Basit_Murattal_192kbps'),
  Voice(id: 'husary', name: Localized('محمود خليل الحصري', 'Al-Husary'), source: 'Husary_128kbps'),
  Voice(id: 'minshawi', name: Localized('محمد صديق المنشاوي', 'Al-Minshawi'), source: 'Minshawy_Murattal_128kbps'),
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
