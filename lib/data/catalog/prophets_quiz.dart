// Needs scholar review before release.
//
// All religious content of the "Heroes of the Prophets" game lives in this
// file. Rules followed here (keep them when editing):
// - Prophets are NEVER depicted: each question has a scenery/object scene only
//   (the Ark, the sea, a star...), no faces, figures or characters.
// - Every prophet's name is followed by "عليه السلام" in Arabic and
//   "(peace be upon him)" in English (checked by test/edu_games_test.dart).
// - Only well-established facts stated plainly in the Quran, paraphrased in
//   simple words for children. No ayah text is quoted here; each fact carries
//   its surah + ayah reference so a scholar can check it.
// - Wrong answers are ordinary, clearly-wrong options, never alternative
//   religious claims.
//
// Flip [reviewedByScholar] to true only after a qualified scholar has signed
// off on every question below (ZADX Islamic Content Reviewer + owner).

import '../../core/localized.dart';

const reviewedByScholar = false;

/// The scenery drawn above a question (never a person).
enum ProphetScene { ark, whale, darkSea, splitSea, kaaba, coolFire, dreamSky, well, ant, hoopoe, garden, night, camel, iron, sunrise }

/// A Quran reference: surah number + name, and an ayah or ayah range.
class QuranRef {
  const QuranRef(this.surah, this.surahName, this.fromAyah, [this.toAyah]);

  final int surah;
  final Localized surahName;
  final int fromAyah;
  final int? toAyah;

  /// "11:37" or "19:29–30".
  String get citation => toAyah == null ? '$surah:$fromAyah' : '$surah:$fromAyah–$toAyah';
}

class ProphetQuestion {
  const ProphetQuestion({
    required this.id,
    required this.scene,
    required this.question,
    required this.answer,
    required this.wrong,
    required this.fact,
    required this.refs,
  });

  final String id;
  final ProphetScene scene;
  final Localized question;
  final Localized answer;
  final List<Localized> wrong;

  /// The paraphrased fact shown after answering ("Did you know?").
  final Localized fact;
  final List<QuranRef> refs;
}

// Surah names used below (number, Arabic, English) and their ayah counts,
// so tests can catch a mistyped reference.
const _baqarah = Localized('البقرة', 'Al-Baqarah');
const _alImran = Localized('آل عمران', 'Al Imran');
const _hud = Localized('هود', 'Hud');
const _yusuf = Localized('يوسف', 'Yusuf');
const _maryam = Localized('مريم', 'Maryam');
const _anbiya = Localized('الأنبياء', 'Al-Anbiya');
const _shuara = Localized('الشعراء', 'Ash-Shu\'ara');
const _naml = Localized('النمل', 'An-Naml');
const _saba = Localized('سبأ', 'Saba');
const _saffat = Localized('الصافات', 'As-Saffat');
const _sad = Localized('ص', 'Sad');

/// Number of ayahs in each surah referenced above.
const surahAyahCounts = <int, int>{2: 286, 3: 200, 11: 123, 12: 111, 19: 98, 21: 112, 26: 227, 27: 93, 34: 54, 37: 182, 38: 88};

/// Prophet names as written in this file, for the honorific test.
const prophetNamesAr = ['آدم', 'نوح', 'إبراهيم', 'إسماعيل', 'يوسف', 'موسى', 'داود', 'سليمان', 'أيوب', 'يونس', 'عيسى', 'صالح'];
const prophetNamesEn = ['Adam', 'Nuh', 'Ibrahim', 'Ismail', 'Yusuf', 'Musa', 'Dawud', 'Sulaiman', 'Ayyub', 'Yunus', 'Isa', 'Salih'];

const prophetQuestions = <ProphetQuestion>[
  ProphetQuestion(
    id: 'adam_names',
    scene: ProphetScene.garden,
    question: Localized('ماذا علّم الله آدم عليه السلام؟', 'What did Allah teach Adam (peace be upon him)?'),
    answer: Localized('أسماء الأشياء كلها', 'The names of all things'),
    wrong: [Localized('الطيران مثل الطيور', 'How to fly like a bird'), Localized('بناء السفن الكبيرة', 'How to build big ships')],
    fact: Localized(
      'آدم عليه السلام هو أول إنسان، وعلّمه الله أسماء الأشياء كلها.',
      'Adam (peace be upon him) was the first human, and Allah taught him the names of all things.',
    ),
    refs: [QuranRef(2, _baqarah, 30, 31)],
  ),
  ProphetQuestion(
    id: 'nuh_ark',
    scene: ProphetScene.ark,
    question: Localized('ماذا أمر الله نوحًا عليه السلام أن يصنع؟', 'What did Allah tell Nuh (peace be upon him) to build?'),
    answer: Localized('سفينة كبيرة', 'A big ship (the Ark)'),
    wrong: [Localized('برجًا عاليًا', 'A tall tower'), Localized('جسرًا فوق النهر', 'A bridge over a river')],
    fact: Localized(
      'أمر الله نوحًا عليه السلام أن يصنع السفينة، وكان الله يرعاه ويعلّمه وهو يصنعها.',
      'Allah told Nuh (peace be upon him) to build the Ark, and Allah watched over him and guided him as he built it.',
    ),
    refs: [QuranRef(11, _hud, 37)],
  ),
  ProphetQuestion(
    id: 'nuh_pairs',
    scene: ProphetScene.ark,
    question: Localized('ماذا حمل نوح عليه السلام في السفينة؟', 'What did Nuh (peace be upon him) carry on the Ark?'),
    answer: Localized('زوجين اثنين من كل نوع، ومعه المؤمنون', 'Two of every kind, and the people who believed'),
    wrong: [Localized('ألعابًا كثيرة فقط', 'Only lots of toys'), Localized('رملًا من الصحراء', 'Sand from the desert')],
    fact: Localized(
      'أمر الله نوحًا عليه السلام أن يحمل في السفينة زوجين اثنين من كل نوع، ومعه من آمن.',
      'Allah told Nuh (peace be upon him) to carry on the Ark two of every kind, together with those who believed.',
    ),
    refs: [QuranRef(11, _hud, 40)],
  ),
  ProphetQuestion(
    id: 'ibrahim_fire',
    scene: ProphetScene.coolFire,
    question: Localized('كيف جعل الله النار لإبراهيم عليه السلام؟', 'What did Allah make the fire for Ibrahim (peace be upon him)?'),
    answer: Localized('بردًا وسلامًا', 'Cool and safe'),
    wrong: [Localized('أكبر وأعلى', 'Bigger and higher'), Localized('ملوّنة بألوان كثيرة', 'Full of many colours')],
    fact: Localized(
      'أمر الله النار أن تكون بردًا وسلامًا على إبراهيم عليه السلام، فلم تؤذه.',
      'Allah commanded the fire to be cool and safe for Ibrahim (peace be upon him), so it did not harm him.',
    ),
    refs: [QuranRef(21, _anbiya, 69)],
  ),
  ProphetQuestion(
    id: 'ibrahim_kaaba',
    scene: ProphetScene.kaaba,
    question: Localized(
      'ما البيت الذي رفع إبراهيم عليه السلام وابنه إسماعيل عليه السلام قواعده؟',
      'Which house did Ibrahim (peace be upon him) and his son Ismail (peace be upon him) build up from its foundations?',
    ),
    answer: Localized('الكعبة', 'The Kaaba'),
    wrong: [Localized('قصر كبير', 'A big palace'), Localized('منارة على البحر', 'A lighthouse by the sea')],
    fact: Localized(
      'رفع إبراهيم عليه السلام وإسماعيل عليه السلام قواعد البيت (الكعبة)، ودعوا الله أن يتقبّل منهما.',
      'Ibrahim (peace be upon him) and Ismail (peace be upon him) raised the foundations of the House (the Kaaba) and asked Allah to accept it from them.',
    ),
    refs: [QuranRef(2, _baqarah, 127)],
  ),
  ProphetQuestion(
    id: 'salih_camel',
    scene: ProphetScene.camel,
    question: Localized(
      'أي حيوان كان آية من الله لقوم صالح عليه السلام؟',
      'Which animal was a sign from Allah for the people of Salih (peace be upon him)?',
    ),
    answer: Localized('ناقة', 'A she-camel'),
    wrong: [Localized('حصان', 'A horse'), Localized('خروف', 'A sheep')],
    fact: Localized(
      'قال صالح عليه السلام لقومه إن هذه الناقة آية من الله، وطلب منهم ألا يؤذوها.',
      'Salih (peace be upon him) told his people that this she-camel was a sign from Allah, and asked them not to harm her.',
    ),
    refs: [QuranRef(11, _hud, 64)],
  ),
  ProphetQuestion(
    id: 'yusuf_dream',
    scene: ProphetScene.dreamSky,
    question: Localized(
      'في منام يوسف عليه السلام رأى أحد عشر كوكبًا ومعها...',
      'In his dream, Yusuf (peace be upon him) saw eleven stars and also...',
    ),
    answer: Localized('الشمس والقمر', 'The sun and the moon'),
    wrong: [Localized('السحاب والمطر', 'Clouds and rain'), Localized('الأشجار والزهور', 'Trees and flowers')],
    fact: Localized(
      'رأى يوسف عليه السلام في منامه أحد عشر كوكبًا والشمس والقمر ساجدين له.',
      'Yusuf (peace be upon him) dreamt that eleven stars, the sun and the moon were bowing down to him.',
    ),
    refs: [QuranRef(12, _yusuf, 4)],
  ),
  ProphetQuestion(
    id: 'yusuf_well',
    scene: ProphetScene.well,
    question: Localized('أين وضع إخوةُ يوسف عليه السلام أخاهم؟', 'Where did the brothers of Yusuf (peace be upon him) put him?'),
    answer: Localized('في قاع بئر', 'At the bottom of a well'),
    wrong: [Localized('فوق جبل', 'On top of a mountain'), Localized('في سفينة', 'On a ship')],
    fact: Localized(
      'اتفق إخوة يوسف عليه السلام أن يضعوه في قاع البئر، وأوحى الله إليه أنه سيخبرهم يومًا بما فعلوا.',
      'The brothers of Yusuf (peace be upon him) agreed to put him at the bottom of a well, and Allah inspired him that one day he would tell them what they had done.',
    ),
    refs: [QuranRef(12, _yusuf, 15)],
  ),
  ProphetQuestion(
    id: 'musa_sea',
    scene: ProphetScene.splitSea,
    question: Localized('بماذا ضرب موسى عليه السلام البحر؟', 'What did Musa (peace be upon him) strike the sea with?'),
    answer: Localized('بعصاه', 'His staff'),
    wrong: [Localized('بحجر', 'A stone'), Localized('بسيف', 'A sword')],
    fact: Localized(
      'أوحى الله إلى موسى عليه السلام أن يضرب البحر بعصاه، فانشقّ البحر.',
      'Allah told Musa (peace be upon him) to strike the sea with his staff, and the sea split apart.',
    ),
    refs: [QuranRef(26, _shuara, 63)],
  ),
  ProphetQuestion(
    id: 'dawud_iron',
    scene: ProphetScene.iron,
    question: Localized('ما الذي ألانه الله لداود عليه السلام؟', 'What did Allah make soft for Dawud (peace be upon him)?'),
    answer: Localized('الحديد', 'Iron'),
    wrong: [Localized('الحجارة', 'Stone'), Localized('الزجاج', 'Glass')],
    fact: Localized(
      'ألان الله الحديد لداود عليه السلام، وعلّمه أن يصنع منه الدروع.',
      'Allah made iron soft for Dawud (peace be upon him) and taught him to make coats of armour from it.',
    ),
    refs: [QuranRef(34, _saba, 10, 11)],
  ),
  ProphetQuestion(
    id: 'sulaiman_ant',
    scene: ProphetScene.ant,
    question: Localized(
      'أي مخلوق صغير سمعه سليمان عليه السلام يحذّر أصحابه؟',
      'Which tiny creature did Sulaiman (peace be upon him) hear warning the others?',
    ),
    answer: Localized('نملة', 'An ant'),
    wrong: [Localized('أسد', 'A lion'), Localized('سمكة', 'A fish')],
    fact: Localized(
      'قالت نملة للنمل: ادخلوا بيوتكم حتى لا يحطمكم سليمان عليه السلام وجنوده وهم لا يشعرون، فتبسّم سليمان عليه السلام ضاحكًا من قولها.',
      'An ant told the other ants to go into their homes so that Sulaiman (peace be upon him) and his soldiers would not crush them without noticing, and Sulaiman (peace be upon him) smiled at what she said.',
    ),
    refs: [QuranRef(27, _naml, 18, 19)],
  ),
  ProphetQuestion(
    id: 'sulaiman_hoopoe',
    scene: ProphetScene.hoopoe,
    question: Localized(
      'أي طائر لاحظ سليمان عليه السلام أنه غائب؟',
      'Which bird did Sulaiman (peace be upon him) notice was missing?',
    ),
    answer: Localized('الهدهد', 'The hoopoe'),
    wrong: [Localized('النسر', 'The eagle'), Localized('الببغاء', 'The parrot')],
    fact: Localized(
      'تفقّد سليمان عليه السلام الطير، فسأل: لماذا لا أرى الهدهد؟',
      'Sulaiman (peace be upon him) checked on the birds and asked why he could not see the hoopoe.',
    ),
    refs: [QuranRef(27, _naml, 20)],
  ),
  ProphetQuestion(
    id: 'ayyub_patience',
    scene: ProphetScene.sunrise,
    question: Localized('بماذا وصف الله أيوب عليه السلام؟', 'How did Allah describe Ayyub (peace be upon him)?'),
    answer: Localized('صابر ونِعم العبد', 'Patient, and an excellent servant'),
    wrong: [Localized('أسرع الناس جريًا', 'The fastest runner'), Localized('أطول الناس', 'The tallest person')],
    fact: Localized(
      'وصف الله أيوب عليه السلام بأنه صابر، ونِعم العبد، وكثير الرجوع إلى الله.',
      'Allah described Ayyub (peace be upon him) as patient, an excellent servant who always turned back to Allah.',
    ),
    refs: [QuranRef(38, _sad, 44)],
  ),
  ProphetQuestion(
    id: 'yunus_whale',
    scene: ProphetScene.whale,
    question: Localized('ماذا التقم يونس عليه السلام في البحر؟', 'What swallowed Yunus (peace be upon him) in the sea?'),
    answer: Localized('حوت كبير', 'A big fish (a whale)'),
    wrong: [Localized('سلطعون', 'A crab'), Localized('نورس', 'A seagull')],
    fact: Localized(
      'التقم الحوتُ يونس عليه السلام في البحر.',
      'A big fish (a whale) swallowed Yunus (peace be upon him) in the sea.',
    ),
    refs: [QuranRef(37, _saffat, 142)],
  ),
  ProphetQuestion(
    id: 'yunus_dua',
    scene: ProphetScene.darkSea,
    question: Localized('ماذا فعل يونس عليه السلام في بطن الحوت؟', 'What did Yunus (peace be upon him) do inside the whale?'),
    answer: Localized('دعا الله وسبّحه', 'He called on Allah and glorified Him'),
    wrong: [Localized('نام طويلًا', 'He slept for a long time'), Localized('غنّى أغنية', 'He sang a song')],
    fact: Localized(
      'نادى يونس عليه السلام ربه في الظلمات، فاستجاب الله له ونجّاه من الغمّ.',
      'In the darkness, Yunus (peace be upon him) called on his Lord, and Allah answered him and saved him from his distress.',
    ),
    refs: [QuranRef(21, _anbiya, 87, 88)],
  ),
  ProphetQuestion(
    id: 'isa_cradle',
    scene: ProphetScene.night,
    question: Localized(
      'ما المعجزة التي حدثت وعيسى عليه السلام طفل صغير في المهد؟',
      'What miracle happened when Isa (peace be upon him) was a baby in the cradle?',
    ),
    answer: Localized('تكلّم مع الناس', 'He spoke to the people'),
    wrong: [Localized('طار في السماء', 'He flew in the sky'), Localized('رسم لوحة كبيرة', 'He painted a big picture')],
    fact: Localized(
      'تكلّم عيسى عليه السلام مع الناس وهو طفل في المهد، وقال إنه عبد الله.',
      'Isa (peace be upon him) spoke to the people while he was still a baby in the cradle, and said that he is a servant of Allah.',
    ),
    refs: [QuranRef(19, _maryam, 29, 30), QuranRef(3, _alImran, 46)],
  ),
];
