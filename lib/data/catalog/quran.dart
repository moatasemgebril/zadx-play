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

/// Reciters. [source] is the EveryAyah folder name (verify licence before release).
const reciters = <Voice>[
  Voice(id: 'afasy', name: Localized('مشاري العفاسي', 'Mishary Alafasy'), source: 'Alafasy_128kbps'),
  Voice(id: 'basit', name: Localized('عبد الباسط عبد الصمد', 'Abdul Basit'), source: 'Abdul_Basit_Murattal_192kbps'),
  Voice(id: 'husary', name: Localized('محمود خليل الحصري', 'Al-Husary'), source: 'Husary_128kbps'),
  Voice(id: 'minshawi', name: Localized('محمد صديق المنشاوي', 'Al-Minshawi'), source: 'Minshawy_Murattal_128kbps'),
  // Whole-surah files (no per-ayah recordings on EveryAyah). QuranicAudio's notice
  // forbids commercial use: get permission or self-host before a paid release.
  Voice(
    id: 'sufi',
    name: Localized('عبد الرشيد صوفي', 'Abdul Rashid Sufi'),
    source: '',
    surahUrl: 'https://download.quranicaudio.com/quran/abdurrashid_sufi/{surah}.mp3',
  ),
];
