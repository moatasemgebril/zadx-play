/// The 28 letters of the Arabic alphabet in the usual teaching (hijā'ī) order.
///
/// Letter shapes are rendered by the font: the positional forms are built by
/// joining the letter to a zero-width joiner (U+200D), so no presentation-form
/// code points are hand-typed here.
class ArabicLetter {
  const ArabicLetter(this.char, this.nameAr, this.nameEn, {this.joinsNext = true});

  /// The isolated letter, e.g. 'ب'.
  final String char;

  /// Letter name in Arabic, e.g. 'باء'.
  final String nameAr;

  /// Simple transliteration for English readers, e.g. 'Baa'.
  final String nameEn;

  /// False for the six letters that never join the letter after them
  /// (ا د ذ ر ز و): they have no separate initial or medial shape.
  final bool joinsNext;

  /// The positions with a distinct shape for this letter.
  List<LetterPosition> get positions => joinsNext
      ? LetterPosition.values
      : const [LetterPosition.isolated, LetterPosition.finalForm];

  /// The letter as it looks in [position].
  String form(LetterPosition position) {
    const zwj = '‍';
    return switch (position) {
      LetterPosition.isolated => char,
      LetterPosition.initial => joinsNext ? '$char$zwj' : char,
      LetterPosition.medial => joinsNext ? '$zwj$char$zwj' : '$zwj$char',
      LetterPosition.finalForm => '$zwj$char',
    };
  }

  @override
  String toString() => 'ArabicLetter($char)';
}

enum LetterPosition { isolated, initial, medial, finalForm }

const arabicLetters = <ArabicLetter>[
  ArabicLetter('ا', 'ألف', 'Alif', joinsNext: false),
  ArabicLetter('ب', 'باء', 'Baa'),
  ArabicLetter('ت', 'تاء', 'Taa'),
  ArabicLetter('ث', 'ثاء', 'Thaa'),
  ArabicLetter('ج', 'جيم', 'Jeem'),
  ArabicLetter('ح', 'حاء', 'Ḥaa'),
  ArabicLetter('خ', 'خاء', 'Khaa'),
  ArabicLetter('د', 'دال', 'Daal', joinsNext: false),
  ArabicLetter('ذ', 'ذال', 'Dhaal', joinsNext: false),
  ArabicLetter('ر', 'راء', 'Raa', joinsNext: false),
  ArabicLetter('ز', 'زاي', 'Zaay', joinsNext: false),
  ArabicLetter('س', 'سين', 'Seen'),
  ArabicLetter('ش', 'شين', 'Sheen'),
  ArabicLetter('ص', 'صاد', 'Ṣaad'),
  ArabicLetter('ض', 'ضاد', 'Ḍaad'),
  ArabicLetter('ط', 'طاء', 'Ṭaa'),
  ArabicLetter('ظ', 'ظاء', 'Ẓaa'),
  ArabicLetter('ع', 'عين', 'ʿAyn'),
  ArabicLetter('غ', 'غين', 'Ghayn'),
  ArabicLetter('ف', 'فاء', 'Faa'),
  ArabicLetter('ق', 'قاف', 'Qaaf'),
  ArabicLetter('ك', 'كاف', 'Kaaf'),
  ArabicLetter('ل', 'لام', 'Laam'),
  ArabicLetter('م', 'ميم', 'Meem'),
  ArabicLetter('ن', 'نون', 'Noon'),
  ArabicLetter('ه', 'هاء', 'Haa'),
  ArabicLetter('و', 'واو', 'Waaw', joinsNext: false),
  ArabicLetter('ي', 'ياء', 'Yaa'),
];

/// Letters that share a skeleton and differ mainly by dots — used as
/// "tricky" distractors in the harder levels.
const lookAlikeGroups = <String>['بتثني', 'جحخ', 'دذ', 'رز', 'سش', 'صض', 'طظ', 'عغ', 'فق'];

List<ArabicLetter> lookAlikesOf(ArabicLetter letter) {
  for (final g in lookAlikeGroups) {
    if (g.contains(letter.char)) {
      return arabicLetters.where((l) => l != letter && g.contains(l.char)).toList();
    }
  }
  return const [];
}
