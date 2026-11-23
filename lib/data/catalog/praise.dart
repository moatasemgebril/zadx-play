import 'dart:math';

import '../../core/app_variant.dart';
import '../models/child_profile.dart';

/// A short praise phrase shown after the child completes a task (Islamic in Zad X Play,
/// neutral in Zad X Kids: see [activePraisePhrases]).
class PraisePhrase {
  const PraisePhrase({required this.masculine, required this.feminine, required this.en});

  /// Arabic, addressing a boy (also used when the form of address is not set).
  final String masculine;

  /// Arabic, addressing a girl.
  final String feminine;
  final String en;

  String text(FormOfAddress? address, String lang) {
    if (lang != 'ar') return en;
    return address == FormOfAddress.feminine ? feminine : masculine;
  }
}

/// Praise phrases (owner request).
///
/// PENDING SHEIKH REVIEW: this list must be approved by the Islamic Content
/// Reviewer before release. Duas and praise only — deliberately NO Quran
/// verses and NO hadith here. Do not add any without a verified source.
// Reviewer note (2026-11-20): جزاك الله خيرًا is a thank-you for a favour; it fits
// best after tasks that help others. Kept for now; sheikh to confirm.
const praisePhrases = <PraisePhrase>[
  PraisePhrase(masculine: 'ما شاء الله، أحسنتَ!', feminine: 'ما شاء الله، أحسنتِ!', en: 'MashaAllah, well done!'),
  PraisePhrase(masculine: 'جزاك الله خيرًا!', feminine: 'جزاكِ الله خيرًا!', en: 'May Allah reward you with good!'),
  PraisePhrase(masculine: 'بارك الله فيك!', feminine: 'بارك الله فيكِ!', en: 'May Allah bless you!'),
  // تبارك is said of Allah only — never address it to the child (reviewer note).
  PraisePhrase(
    masculine: 'ما شاء الله تبارك الله! كمِّل كده',
    feminine: 'ما شاء الله تبارك الله! كمِّلي كده',
    en: 'MashaAllah, blessed is Allah! Keep it up!',
  ),
  PraisePhrase(
    masculine: 'جعله الله في ميزان حسناتك',
    feminine: 'جعله الله في ميزان حسناتكِ',
    en: 'May Allah place it in your scale of good deeds',
  ),
  PraisePhrase(masculine: 'نفع الله بك!', feminine: 'نفع الله بكِ!', en: 'May Allah benefit others through you!'),
];

/// Neutral praise of Zad X Kids (owner decision 2026-11-22): no religious wording, gender-aware
/// in Arabic like the Islamic list. Scanned for religious words by test/kids_variant_test.dart.
const kidsPraisePhrases = <PraisePhrase>[
  PraisePhrase(masculine: 'أحسنتَ!', feminine: 'أحسنتِ!', en: 'Great job!'),
  PraisePhrase(masculine: 'برافو عليك!', feminine: 'برافو عليكِ!', en: 'Bravo!'),
  PraisePhrase(masculine: 'شاطر! كمِّل كده', feminine: 'شاطرة! كمِّلي كده', en: 'Well done! Keep it up!'),
  PraisePhrase(masculine: 'إنت بطل!', feminine: 'إنتِ بطلة!', en: "You're a star!"),
  PraisePhrase(masculine: 'فخورين بيك!', feminine: 'فخورين بيكِ!', en: "We're proud of you!"),
  PraisePhrase(masculine: 'شغل جميل يا بطل!', feminine: 'شغل جميل يا بطلة!', en: 'Amazing work!'),
];

/// The praise list of this build.
const activePraisePhrases = kIsKids ? kidsPraisePhrases : praisePhrases;

/// Picks a random praise phrase, never the same one twice in a row.
class PraisePicker {
  PraisePicker([Random? random, this.phrases = activePraisePhrases]) : _random = random ?? Random();

  final Random _random;
  final List<PraisePhrase> phrases;
  int? _last;

  /// Next phrase text for the child's [address] (null = not set) in [lang].
  String next(FormOfAddress? address, String lang) => nextPhrase().text(address, lang);

  PraisePhrase nextPhrase() {
    if (phrases.length < 2) return phrases.single;
    final last = _last;
    var i = _random.nextInt(last == null ? phrases.length : phrases.length - 1);
    // Skip over the previous index so it can never come up again immediately.
    if (last != null && i >= last) i++;
    _last = i;
    return phrases[i];
  }
}
