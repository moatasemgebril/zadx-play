/// Text of the Zad X Kids build (docs/decisions/ZADX-KIDS-VARIANT.md).
///
/// The shared ARB files (lib/l10n/app_*.arb) belong to the Islamic app. In the Kids build
/// `KidsLocalizations` (kids_localizations.dart) replaces:
/// * every key in [kidsRewrites] with the neutral text below, and
/// * every key in [islamicOnlyL10nKeys] with an empty string. Those keys are used only by
///   Islamic-only screens (Quran, prayer, adhan, adhkar, mosque, prophets) that do not exist in the
///   Kids build; the empty string is a second safety net.
///
/// test/kids_variant_test.dart applies both to the ARB files and fails if any religious word
/// (tools/kids_forbidden_words.json) is left, so a new religious ARB string must be added here.
library;

import '../core/localized.dart';

/// Neutral replacements for shared strings, per language (`en`, `ar`). Placeholders must match
/// the ARB placeholders exactly (checked by the test).
const Map<String, Map<String, String>> kidsRewrites = {
  'en': {
    'greet': 'Hello, champ!',
    'homeHeroSub': "Let's start the day with tasks and reading",
    'avatarMoon': 'Planet',
    'deviceGamesNote': 'Unlock after tasks, lock at study time and bedtime',
    'lockRequired': 'Finish the must-do tasks first, like homework',
    'settingsTitle': 'Settings',
    'assistantHello':
        "Hi! I'm the Zad X assistant. Ask me about unlocking games, study time, bedtime, reading time, tasks or PlayStation.",
    'how1B':
        'When you first open Zad X, create the parent PIN, then add your child from the Parent dashboard and set study time, bedtime and reading time.',
    'how5T': 'Schedules lock play',
    'how5B':
        'During study time, reading time and bedtime, apps lock by themselves and open again when the time is over. Bedtime locks at night and opens in the morning.',
    'faq2Q': 'What happens at bedtime?',
    'faq2A':
        'Apps lock by themselves at the bedtime you set and open again in the morning. Phone and emergency calls always work.',
    'faq3Q': 'How do I set study time, bedtime and reading time?',
    'faq3A': 'Open the Parent dashboard with your PIN, then "Schedules": turn each one on and pick its start and end time.',
    'faq6A': "The same Zad X app on your phone and on your child's phone or tablet.",
    'featLock': 'Device lock with study, bedtime and reading schedules + daily limit (1 child)',
    'upgradeBody':
        'The device lock with study, bedtime and reading schedules is free, with no subscription. Paid plans add games, tasks & rewards, exercises and more.',
    'deviceLockDesc':
        'All games and apps (like Facebook, YouTube and the browser) stay locked until tasks are done and during study time, reading time and bedtime, except the allowed apps.',
    'deviceLockDescFree':
        'All games and apps (like Facebook, YouTube and the browser) lock during study time, reading time and bedtime, and when the daily screen time runs out, except the allowed apps.',
    'lockDisclosureBody':
        "Zad X will see which app is open on this phone (only the app's name, never what is on the screen) so it can lock apps until tasks are done and during the times you schedule. Phone and emergency calls are never locked. Nothing about the apps used leaves this phone.\n\nOn the next screen, turn on \"Zad X\" in Accessibility settings.",
    'eduRoundDone': 'Great job! Round complete!',
  },
  'ar': {
    'greet': 'أهلاً يا بطل!',
    'homeHeroSub': 'يلا نبدأ يومنا بالمهام والقراية',
    'avatarMoon': 'كوكب',
    'deviceGamesNote': 'بتتفتح بعد المهام وبتقفل وقت المذاكرة والنوم',
    'lockRequired': 'خلّص المهام الأساسية الأول، زي الواجب',
    'settingsTitle': 'الإعدادات',
    'assistantHello':
        'أهلاً بيك! أنا مساعد Zad X. اسألني عن فتح الألعاب، أو وقت المذاكرة، أو وقت النوم، أو وقت القراية، أو المهام، أو البلايستيشن.',
    'how1B':
        'أول ما تفتح Zad X اعمل الرقم السري لولي الأمر، وبعدين ضيف ابنك من لوحة ولي الأمر، وحدد وقت المذاكرة والنوم والقراية.',
    'how5T': 'المواعيد بتقفل اللعب',
    'how5B':
        'في وقت المذاكرة والقراية والنوم التطبيقات بتتقفل لوحدها وبتتفتح تاني لما الوقت يخلص. وقت النوم بيقفل بالليل ويفتح الصبح.',
    'faq2Q': 'إيه اللي بيحصل وقت النوم؟',
    'faq2A': 'التطبيقات بتتقفل لوحدها في ميعاد النوم اللي انت حددته وبتتفتح تاني الصبح. التليفون ومكالمات الطوارئ شغالين دايمًا.',
    'faq3Q': 'إزاي أحدد وقت المذاكرة والنوم والقراية؟',
    'faq3A': 'ادخل لوحة ولي الأمر بالرقم السري، وبعدين "المواعيد": شغّل كل ميعاد واختار وقت البداية والنهاية.',
    'faq6A': 'نفس تطبيق Zad X على تليفونك وعلى تليفون أو تابلت ابنك.',
    'featLock': 'قفل الأجهزة بمواعيد المذاكرة والنوم والقراية وحد يومي (طفل واحد)',
    'upgradeBody':
        'قفل الأجهزة بمواعيد المذاكرة والنوم والقراية مجانًا بلا اشتراك. الباقات المدفوعة بتضيف الألعاب والمهام والمكافآت والتمارين وأكتر.',
    'deviceLockDesc':
        'كل الألعاب والتطبيقات (زي فيسبوك ويوتيوب والمتصفح) تتقفل لحد ما الطفل يخلّص مهامه، وفي وقت المذاكرة والقراية والنوم، ما عدا التطبيقات المسموحة.',
    'deviceLockDescFree':
        'كل الألعاب والتطبيقات (زي فيسبوك ويوتيوب والمتصفح) بتتقفل في وقت المذاكرة والقراية والنوم، ولما وقت الشاشة اليومي يخلص، ما عدا التطبيقات المسموحة.',
    'lockDisclosureBody':
        'Zad X هيعرف أنهي تطبيق مفتوح على التليفون ده (اسم التطبيق بس، عمره ما بيقرا اللي على الشاشة) عشان يقفل التطبيقات لحد ما المهام تخلص وفي المواعيد اللي انت بتحددها. التليفون ومكالمات الطوارئ عمرهم ما بيتقفلوا. ومفيش أي معلومة عن التطبيقات بتخرج من التليفون.\n\nفي الصفحة الجاية، فعّل "Zad X" في إعدادات تسهيل الاستخدام.',
    'eduRoundDone': 'برافو! خلّصت الجولة',
  },
};

/// ARB keys used only by Zad X Play features (Islamic features + the Arabic Letters game).
/// Empty in the Kids build.
const Set<String> islamicOnlyL10nKeys = {
  // Tabs, home cards, prayer names and the adhan.
  'tabQuran', 'prayerToday', 'nextPrayer', 'fajr', 'dhuhr', 'asr', 'maghrib', 'isha',
  'adhanTitle', 'chooseMuezzin', 'hearAdhan',
  // Prayer lock ("I prayed").
  'lockPrayer', 'prayerNow', 'prayerSub', 'iPrayed', 'childPrayerLocked', 'deviceLockFreePrayerNote',
  // Quran + adhkar screens.
  'quran', 'chooseReciter', 'ayatCount', 'playSurah', 'readSurah', 'hideSurahText', 'juz30', 'juz29',
  'adhkar', 'morningAdhkar', 'eveningAdhkar', 'salawat', 'sectionDone', 'loadingText', 'textError',
  'recitationComingSoon', 'licencePending',
  // Consoles: adhan alerts and play windows between prayers.
  'psNotifyAdhan', 'psSchedule', 'psAlertAdhan', 'msAlertAdhan', 'afterDhuhr', 'afterAsr', 'afterMaghrib',
  // Windows Zad X Guard (computes prayer locks; not offered in Kids v1).
  'computerNote',
  // Settings: adhan lock, prayer calculation, sacred-audio note.
  'lockAtAdhan', 'method', 'asrCalc', 'asrStandard', 'asrHanafi', 'soundSacredNote',
  // Plans: Islamic features and the Ramadan offer.
  'featPrayer', 'featQuran', 'featAdhkar', 'offer3',
  // Learning games: mosque builder, prophets quiz, scholar-review note. The Arabic Letters game is
  // Zad X Play only too (Zad X Kids targets the US / Europe; owner decision 2026-11-22).
  'zadGameLetters', 'zadGameProphets', 'zadGameMasjid', 'eduGoBuild', 'mosqueNext', 'mosqueBuild', 'mosqueCost',
  'mosqueNeedStars', 'mosqueComplete', 'mosqueBuiltPart', 'mosquePartsDone', 'prophetsIntro',
  'prophetsDidYouKnow', 'prophetsRef', 'parentReviewNote',
};

/// The Kids text for [key] in [lang], or null when the shared ARB text is used.
String? kidsText(String lang, String key) {
  if (islamicOnlyL10nKeys.contains(key)) return '';
  return (kidsRewrites[lang] ?? kidsRewrites['en']!)[key];
}

/// Kids-only UI text that has no ARB key (schedules, wordmark). Arabic first, like the ARB files.
abstract final class KidsText {
  static const wordmarkKids = Localized('Kids', 'Kids');

  static const schedulesTitle = Localized('المواعيد', 'Schedules');
  static const schedulesNote = Localized(
    'التطبيقات بتتقفل لوحدها في المواعيد دي (ما عدا التليفون والطوارئ والتطبيقات المسموحة).',
    'Apps lock by themselves at these times (except phone, emergency and allowed apps).',
  );
  static const study = Localized('وقت المذاكرة', 'Study time');
  static const studyNote = Localized('الواجب والمذاكرة الأول', 'Homework and study first');
  static const bedtime = Localized('وقت النوم', 'Bedtime');
  static const bedtimeNote = Localized('بيقفل بالليل ويفتح الصبح', 'Locks at night, opens in the morning');
  static const reading = Localized('وقت القراية', 'Reading time');
  static const readingNote = Localized('ميعاد كل يوم لكتاب أو قصة', 'A daily slot for a book or a story');
  static const from = Localized('من', 'From');
  static const to = Localized('لحد', 'To');
  static const days = Localized('الأيام', 'Days');
  static const todayTitle = Localized('مواعيد النهارده', "Today's schedule");
  static const off = Localized('متوقف', 'Off');
  static const lockedNow = Localized('مقفول دلوقتي', 'Locked now');
  static const childScheduleLocked = Localized('ميعاد قفل — التطبيقات مقفولة', 'Scheduled lock — apps locked');

  /// Games screen banner while a schedule locks the device.
  static const lockStudy = Localized('وقت المذاكرة — التطبيقات هتتفتح لما الوقت يخلص', 'Study time — apps open again when it is over');
  static const lockBedtime = Localized('وقت النوم — نوم الهنا! التطبيقات هتتفتح الصبح', 'Bedtime — sleep well! Apps open in the morning');
  static const lockReading = Localized('وقت القراية — هات كتاب أو قصة!', 'Reading time — grab a book or a story!');

  /// Monday first (DateTime.monday == 1).
  static const weekdays = [
    Localized('إثنين', 'Mon'),
    Localized('ثلاثاء', 'Tue'),
    Localized('أربعاء', 'Wed'),
    Localized('خميس', 'Thu'),
    Localized('جمعة', 'Fri'),
    Localized('سبت', 'Sat'),
    Localized('أحد', 'Sun'),
  ];
}
