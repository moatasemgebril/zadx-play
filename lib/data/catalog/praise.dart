import 'dart:math';

import '../models/child_profile.dart';

/// A short Islamic praise phrase shown after the child completes a task.
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
const praisePhrases = <PraisePhrase>[
  PraisePhrase(masculine: 'ما شاء الله، أحسنت!', feminine: 'ما شاء الله، أحسنتِ!', en: "Masha'Allah, well done!"),
  PraisePhrase(masculine: 'جزاك الله خيرًا!', feminine: 'جزاكِ الله خيرًا!', en: 'May Allah reward you with good!'),
  PraisePhrase(masculine: 'بارك الله فيك!', feminine: 'بارك الله فيكِ!', en: 'May Allah bless you!'),
  PraisePhrase(masculine: 'تبارك الله! كمّل كده', feminine: 'تبارك الله! كمّلي كده', en: 'Tabarak Allah! Keep it up!'),
  PraisePhrase(
    masculine: 'جعله الله في ميزان حسناتك',
    feminine: 'جعله الله في ميزان حسناتك',
    en: 'May Allah place it in your scale of good deeds',
  ),
  PraisePhrase(masculine: 'نفع الله بك!', feminine: 'نفع الله بكِ!', en: 'May Allah make you a benefit to others!'),
];

/// Picks a random praise phrase, never the same one twice in a row.
class PraisePicker {
  PraisePicker([Random? random, this.phrases = praisePhrases]) : _random = random ?? Random();

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
