import '../../core/localized.dart';

enum AdhkarSection { morning, evening, salawat }

/// One remembrance with how many times it is said.
class Dhikr {
  const Dhikr({required this.id, required this.text, required this.times, required this.source, this.note});

  final String id;
  final String text; // Arabic text, recited in Arabic in every language
  final int times;
  final String source; // Arabic name of the hadith collection

  /// Shown under the text, outside what is recited (e.g. ﷺ after the Prophet's name).
  final Localized? note;

  /// The source in the reader's language (English names for non-Arabic UIs).
  String sourceOf(String lang) => lang == 'ar' ? source : (dhikrSourcesEn[source] ?? source);
}

/// English names of the hadith collections used in [Dhikr.source].
const dhikrSourcesEn = <String, String>{
  'مسلم': 'Muslim',
  'البخاري': 'Al-Bukhari',
  'الترمذي': 'At-Tirmidhi',
  'أبو داود': 'Abu Dawud',
  'أبو داود والترمذي': 'Abu Dawud and At-Tirmidhi',
  'الترمذي وغيره': 'At-Tirmidhi and others',
};

/// Morning/evening adhkar and salawat, from Hisn al-Muslim (Sa'id al-Qahtani).
///
/// Owner decision 2026-11-22: texts, counts and sources are checked against
/// trusted published sources (URLs next to each item) instead of a sheikh
/// sign-off. Copy any new text verbatim from its cited page; ids must be unique.
///
/// Verified counts: bismillah 3, hasbi 7, subhan 100, bika 1, ibrahimiya 1.
const adhkar = <AdhkarSection, List<Dhikr>>{
  AdhkarSection.morning: [
    // Sahih Muslim (Ibn Mas'ud): https://hadeethenc.com/ar/browse/hadith/3008
    // TODO(content): complete with «رب أسألك خير ما في هذا اليوم…» copied verbatim from
    // the page above (could not be fetched verbatim on 2026-11-22; text left unchanged).
    Dhikr(id: 'm_asbahna', times: 1, source: 'مسلم', text: 'أَصْبَحْنَا وَأَصْبَحَ الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ'),
    Dhikr(id: 'm_bika', times: 1, source: 'الترمذي', text: 'اللَّهُمَّ بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ النُّشُورُ'),
    Dhikr(id: 'm_bismillah', times: 3, source: 'أبو داود والترمذي', text: 'بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ'),
    // Hisn al-Muslim 87 (At-Tirmidhi and others): https://sunnah.com/hisn:87
    // ﷺ is shown as a note, outside the recited wording.
    Dhikr(id: 'm_radeetu', times: 3, source: 'الترمذي وغيره', note: Localized('محمد ﷺ', 'Muhammad ﷺ'), text: 'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ نَبِيًّا'),
    Dhikr(id: 'm_hasbi', times: 7, source: 'أبو داود', text: 'حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ عَلَيْهِ تَوَكَّلْتُ وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ'),
    Dhikr(id: 'm_subhan', times: 100, source: 'مسلم', text: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ'),
  ],
  AdhkarSection.evening: [
    // Sahih Muslim (Ibn Mas'ud): https://hadeethenc.com/ar/browse/hadith/3008
    // TODO(content): complete with «رب أسألك خير ما في هذه الليلة…» copied verbatim from
    // the page above (could not be fetched verbatim on 2026-11-22; text left unchanged).
    Dhikr(id: 'e_amsayna', times: 1, source: 'مسلم', text: 'أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ، وَالْحَمْدُ لِلَّهِ، لَا إِلَهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ'),
    Dhikr(id: 'e_bika', times: 1, source: 'الترمذي', text: 'اللَّهُمَّ بِكَ أَمْسَيْنَا، وَبِكَ أَصْبَحْنَا، وَبِكَ نَحْيَا، وَبِكَ نَمُوتُ، وَإِلَيْكَ الْمَصِيرُ'),
    // Hisn al-Muslim 97 (At-Tirmidhi): https://sunnah.com/hisn:97
    Dhikr(id: 'e_kalimat', times: 3, source: 'الترمذي', text: 'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ'),
    Dhikr(id: 'e_bismillah', times: 3, source: 'أبو داود والترمذي', text: 'بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ'),
    Dhikr(id: 'e_hasbi', times: 7, source: 'أبو داود', text: 'حَسْبِيَ اللَّهُ لَا إِلَهَ إِلَّا هُوَ عَلَيْهِ تَوَكَّلْتُ وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ'),
    Dhikr(id: 'e_subhan', times: 100, source: 'مسلم', text: 'سُبْحَانَ اللَّهِ وَبِحَمْدِهِ'),
  ],
  AdhkarSection.salawat: [
    // The former "s_short" item (10 times, At-Tabarani: «من صلى علي حين يصبح عشرا…») was removed:
    // that hadith is weak (al-Albani, Silsila ad-Da'ifa 5788). See [salawatReminder] instead.
    Dhikr(id: 's_ibrahimiya', times: 1, source: 'البخاري', text: 'اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ، كَمَا صَلَّيْتَ عَلَى إِبْرَاهِيمَ وَعَلَى آلِ إِبْرَاهِيمَ، إِنَّكَ حَمِيدٌ مَجِيدٌ، اللَّهُمَّ بَارِكْ عَلَى مُحَمَّدٍ وَعَلَى آلِ مُحَمَّدٍ، كَمَا بَارَكْتَ عَلَى إِبْرَاهِيمَ وَعَلَى آلِ إِبْرَاهِيمَ، إِنَّكَ حَمِيدٌ مَجِيدٌ'),
  ],
};

/// The three Quls are said 3 times morning and evening; shown as a reminder card.
const qulsReminder = Localized(
  'اقرأ الإخلاص والفلق والناس ٣ مرات',
  'Recite Al-Ikhlas, Al-Falaq and An-Nas 3 times',
);

/// A count-free reminder shown above the salawat (no number, no reward claim).
const salawatReminder = Localized(
  'أكثِروا من الصلاة على النبي ﷺ',
  'Send blessings upon the Prophet ﷺ often',
);

/// Minutes of play time earned when a full section is completed.
const adhkarRewardMinutes = 10;
