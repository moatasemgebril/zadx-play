import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_ar.dart';
import '../l10n/app_localizations_en.dart';
import 'kids_strings.dart';

/// Localizations of the Zad X Kids build: the shared ARB text with every religious string
/// replaced (see kids_strings.dart). Installed by `ZadXApp` instead of `AppLocalizations.delegate`
/// when `kIsKids`, so every `context.l10n.x` in shared screens returns the Kids text.
class KidsLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const KidsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.delegate.isSupported(locale);

  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture<AppLocalizations>(kidsLocalizationsFor(locale));

  @override
  bool shouldReload(KidsLocalizationsDelegate old) => false;
}

/// The Kids localizations for [locale] (Arabic unless English).
AppLocalizations kidsLocalizationsFor(Locale locale) =>
    locale.languageCode == 'en' ? KidsLocalizationsEn() : KidsLocalizationsAr();

class KidsLocalizationsAr extends AppLocalizationsAr with KidsL10nOverrides {
  KidsLocalizationsAr() : super('ar');
}

class KidsLocalizationsEn extends AppLocalizationsEn with KidsL10nOverrides {
  KidsLocalizationsEn() : super('en');
}

/// One override per key of [kidsRewrites], [islamicOnlyL10nKeys] and [kidsHiddenL10nKeys]
/// (test/kids_variant_test.dart checks that none is missing). Generated from the ARB metadata;
/// keep the parameter names identical to the ARB placeholders.
mixin KidsL10nOverrides on AppLocalizations {
  String get _lang => localeName.split(RegExp('[_-]')).first;

  String _text(String key) => kidsText(_lang, key) ?? '';

  String _fill(String key, Map<String, String> values) {
    var s = _text(key);
    values.forEach((name, value) => s = s.replaceAll('{$name}', value));
    return s;
  }

  @override
  String get greet => _text('greet');

  @override
  String get homeHeroSub => _text('homeHeroSub');

  @override
  String get zadGameLetters => _text('zadGameLetters');

  @override
  String get avatarMoon => _text('avatarMoon');

  @override
  String get deviceGamesNote => _text('deviceGamesNote');

  @override
  String get lockRequired => _text('lockRequired');

  @override
  String get settingsTitle => _text('settingsTitle');

  @override
  String get assistantHello => _text('assistantHello');

  @override
  String get how1B => _text('how1B');

  @override
  String get how5T => _text('how5T');

  @override
  String get how5B => _text('how5B');

  @override
  String get faq2Q => _text('faq2Q');

  @override
  String get faq2A => _text('faq2A');

  @override
  String get faq3Q => _text('faq3Q');

  @override
  String get faq3A => _text('faq3A');

  @override
  String get faq6A => _text('faq6A');

  @override
  String get featLock => _text('featLock');

  @override
  String get upgradeBody => _text('upgradeBody');

  @override
  String get deviceLockDesc => _text('deviceLockDesc');

  @override
  String get deviceLockDescFree => _text('deviceLockDescFree');

  @override
  String get lockDisclosureBody => _text('lockDisclosureBody');

  @override
  String get eduRoundDone => _text('eduRoundDone');

  @override
  String get lockedKidBody => _text('lockedKidBody');

  @override
  String get assistantParentOnlyBody => _text('assistantParentOnlyBody');

  @override
  String get pairNote => _text('pairNote');

  @override
  String get psScheduleNote => _text('psScheduleNote');

  @override
  String get msScheduleNote => _text('msScheduleNote');

  @override
  String get formOfAddress => _text('formOfAddress');

  @override
  String get addressNotSet => _text('addressNotSet');

  @override
  String get addressBoy => _text('addressBoy');

  @override
  String get addressGirl => _text('addressGirl');

  @override
  String get downloadWindows => _text('downloadWindows');

  @override
  String get tabQuran => _text('tabQuran');

  @override
  String get prayerToday => _text('prayerToday');

  @override
  String nextPrayer(String name, String time) => _fill('nextPrayer', {'name': name, 'time': time});

  @override
  String get fajr => _text('fajr');

  @override
  String get dhuhr => _text('dhuhr');

  @override
  String get asr => _text('asr');

  @override
  String get maghrib => _text('maghrib');

  @override
  String get isha => _text('isha');

  @override
  String get adhanTitle => _text('adhanTitle');

  @override
  String get chooseMuezzin => _text('chooseMuezzin');

  @override
  String get hearAdhan => _text('hearAdhan');

  @override
  String get lockPrayer => _text('lockPrayer');

  @override
  String prayerNow(String name) => _fill('prayerNow', {'name': name});

  @override
  String get prayerSub => _text('prayerSub');

  @override
  String get iPrayed => _text('iPrayed');

  @override
  String get childPrayerLocked => _text('childPrayerLocked');

  @override
  String deviceLockFreePrayerNote(String n) => _fill('deviceLockFreePrayerNote', {'n': n});

  @override
  String get quran => _text('quran');

  @override
  String get chooseReciter => _text('chooseReciter');

  @override
  String ayatCount(String n) => _fill('ayatCount', {'n': n});

  @override
  String playSurah(String name) => _fill('playSurah', {'name': name});

  @override
  String readSurah(String name) => _fill('readSurah', {'name': name});

  @override
  String get hideSurahText => _text('hideSurahText');

  @override
  String get juz30 => _text('juz30');

  @override
  String get juz29 => _text('juz29');

  @override
  String get adhkar => _text('adhkar');

  @override
  String get morningAdhkar => _text('morningAdhkar');

  @override
  String get eveningAdhkar => _text('eveningAdhkar');

  @override
  String get salawat => _text('salawat');

  @override
  String get sectionDone => _text('sectionDone');

  @override
  String get loadingText => _text('loadingText');

  @override
  String get textError => _text('textError');

  @override
  String get recitationComingSoon => _text('recitationComingSoon');

  @override
  String get licencePending => _text('licencePending');

  @override
  String get psNotifyAdhan => _text('psNotifyAdhan');

  @override
  String get psSchedule => _text('psSchedule');

  @override
  String get psAlertAdhan => _text('psAlertAdhan');

  @override
  String get msAlertAdhan => _text('msAlertAdhan');

  @override
  String get afterDhuhr => _text('afterDhuhr');

  @override
  String get afterAsr => _text('afterAsr');

  @override
  String get afterMaghrib => _text('afterMaghrib');

  @override
  String get computerNote => _text('computerNote');

  @override
  String get lockAtAdhan => _text('lockAtAdhan');

  @override
  String get method => _text('method');

  @override
  String get asrCalc => _text('asrCalc');

  @override
  String get asrStandard => _text('asrStandard');

  @override
  String get asrHanafi => _text('asrHanafi');

  @override
  String get soundSacredNote => _text('soundSacredNote');

  @override
  String get featPrayer => _text('featPrayer');

  @override
  String get featQuran => _text('featQuran');

  @override
  String get featAdhkar => _text('featAdhkar');

  @override
  String get offer3 => _text('offer3');

  @override
  String get zadGameProphets => _text('zadGameProphets');

  @override
  String get zadGameMasjid => _text('zadGameMasjid');

  @override
  String get eduGoBuild => _text('eduGoBuild');

  @override
  String mosqueNext(String part) => _fill('mosqueNext', {'part': part});

  @override
  String get mosqueBuild => _text('mosqueBuild');

  @override
  String mosqueCost(String n) => _fill('mosqueCost', {'n': n});

  @override
  String mosqueNeedStars(String n) => _fill('mosqueNeedStars', {'n': n});

  @override
  String get mosqueComplete => _text('mosqueComplete');

  @override
  String mosqueBuiltPart(String part) => _fill('mosqueBuiltPart', {'part': part});

  @override
  String mosquePartsDone(String done, String total) => _fill('mosquePartsDone', {'done': done, 'total': total});

  @override
  String get prophetsIntro => _text('prophetsIntro');

  @override
  String get prophetsDidYouKnow => _text('prophetsDidYouKnow');

  @override
  String prophetsRef(String surah, String ref) => _fill('prophetsRef', {'surah': surah, 'ref': ref});

  @override
  String get parentReviewNote => _text('parentReviewNote');
}
