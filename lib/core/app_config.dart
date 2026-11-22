import 'app_variant.dart';

/// Brand + store constants of the Islamic app, "Zad X Play".
abstract final class IslamicBrand {
  static const storeName = 'Zad X Play';

  /// Who Zad X Play is for (owner request 2026-11-22): shown on the launch splash and in Help,
  /// in both languages. Short and dignified; never used in Zad X Kids.
  static const identityAr = 'لأطفال المسلمين';
  static const identityEn = 'For Muslim Kids';

  /// The identity line in [lang] (Arabic unless English).
  static String identityFor(String lang) => lang == 'en' ? identityEn : identityAr;

  /// App Store subtitle (≤ 30 characters, checked by test/launch_splash_test.dart).
  static const storeSubtitleAr = 'للأطفال المسلمين: صلاة ثم لعب';
  static const storeSubtitleEn = 'Muslim kids: pray, then play';

  /// Google Play short description (≤ 80 characters): the identity + what the app does.
  static const storeShortDescriptionAr = 'للأطفال المسلمين: ألعاب بعد الصلاة والمهام، ومواقيت وأذان وقرآن وقفل';
  static const storeShortDescriptionEn = 'For Muslim kids: games unlock after prayer & tasks. Prayer times, adhan, Quran';
  static const androidPackage = 'com.zadx.app';
  static const iosBundleId = 'com.zadx.app';
  static const iosAppGroup = 'group.com.zadx.app';
  static const productBasicMonthly = 'zadx_basic_monthly';
  static const productBasicYearly = 'zadx_basic_yearly';
  static const productPlusMonthly = 'zadx_plus_monthly';
  static const productPlusYearly = 'zadx_plus_yearly';
}

/// Brand + store constants of the non-religious app, "Zad X Kids" (docs/decisions/ZADX-KIDS-VARIANT.md).
/// Separate store listing, app id and subscription products; same Zad X brand.
/// Scanned for religious words by test/kids_variant_test.dart.
abstract final class KidsBrand {
  static const storeName = 'Zad X Kids';
  static const storeSubtitleAr = 'وقت الشاشة بعد المهام والواجب'; // ≤ 30 (App Store)
  static const storeSubtitleEn = 'Screen time after tasks & homework';
  static const storeShortDescriptionAr = 'وقت الشاشة بعد المهام والمذاكرة، مع مواعيد للمذاكرة والقراءة والنوم';
  static const storeShortDescriptionEn = 'Screen time after tasks & homework, with study, reading and bedtime schedules';
  static const androidPackage = 'com.zadx.kids';
  static const iosBundleId = 'com.zadx.kids';
  static const iosAppGroup = 'group.com.zadx.kids';
  static const productBasicMonthly = 'zadx_kids_basic_monthly';
  static const productBasicYearly = 'zadx_kids_basic_yearly';
  static const productPlusMonthly = 'zadx_kids_plus_monthly';
  static const productPlusYearly = 'zadx_kids_plus_yearly';
}

/// Single place for brand and business constants.
///
/// Store listing name approved: "Zad X Play". Parent keywords go in the
/// subtitle (see [storeSubtitleAr]), not in the name. The Zad X Kids build
/// (`--dart-define=ZADX_VARIANT=kids`) gets the [KidsBrand] values instead.
class AppConfig {
  const AppConfig._();

  /// Brand name shown inside the app (logo, titles). The same in both apps.
  static const brandName = 'Zad X';

  /// Name used for the store listing / launcher label.
  /// Keep in sync with android:label and CFBundleDisplayName (android/scripts/integrate_native.py).
  static const storeName = kIsKids ? KidsBrand.storeName : IslamicBrand.storeName;

  /// App Store subtitle (≤ 30 characters). Zad X Play says it is for Muslim kids.
  static const storeSubtitleAr = kIsKids ? KidsBrand.storeSubtitleAr : IslamicBrand.storeSubtitleAr;
  static const storeSubtitleEn = kIsKids ? KidsBrand.storeSubtitleEn : IslamicBrand.storeSubtitleEn;

  /// Google Play short description (≤ 80 characters).
  static const storeShortDescriptionAr =
      kIsKids ? KidsBrand.storeShortDescriptionAr : IslamicBrand.storeShortDescriptionAr;
  static const storeShortDescriptionEn =
      kIsKids ? KidsBrand.storeShortDescriptionEn : IslamicBrand.storeShortDescriptionEn;

  static const androidPackage = kIsKids ? KidsBrand.androidPackage : IslamicBrand.androidPackage;
  static const iosBundleId = kIsKids ? KidsBrand.iosBundleId : IslamicBrand.iosBundleId;

  /// Shared container used by the iOS app + extensions (App Group).
  static const iosAppGroup = kIsKids ? KidsBrand.iosAppGroup : IslamicBrand.iosAppGroup;

  // Subscription product ids (must match App Store Connect / Play Console). Each app has its own
  // products; backend/functions/src/security.ts (`PRODUCTS`) maps both sets to the same tiers.
  static const productBasicMonthly = kIsKids ? KidsBrand.productBasicMonthly : IslamicBrand.productBasicMonthly;
  static const productBasicYearly = kIsKids ? KidsBrand.productBasicYearly : IslamicBrand.productBasicYearly;
  static const productPlusMonthly = kIsKids ? KidsBrand.productPlusMonthly : IslamicBrand.productPlusMonthly;
  static const productPlusYearly = kIsKids ? KidsBrand.productPlusYearly : IslamicBrand.productPlusYearly;

  static const Set<String> allProductIds = {
    productBasicMonthly,
    productBasicYearly,
    productPlusMonthly,
    productPlusYearly,
  };

  /// Plus trial from the first launch, kept on the device (owner decision 2026-11-21).
  /// See `TrialClock` in lib/services/billing/trial_clock.dart. Store intro offers, if any,
  /// must not promise a longer trial.
  static const trialDays = 7;

  /// Referral rewards: friends who paid -> free months.
  static const referralRewards = {1: 2, 2: 4, 3: 6};
  static const referralMaxFriendsPerYear = 3;

  /// Minutes deducted when a child opens a controlled game session.
  static const sessionMinutes = 15;

  /// Grace minutes after the adhan before the next play window starts.
  static const playWindowAfterPrayerMinutes = 20;
  static const playWindowBeforePrayerMinutes = 10;

  /// Companion parental-control apps for consoles and PCs (no public control API,
  /// so Zad X alerts the parent and opens the official app).
  static const playStationFamilyAndroid = 'com.playstation.ohana.android';
  static const playStationFamilyWeb = 'https://www.playstation.com/familyapp';
  static const microsoftFamilyAndroid = 'com.microsoft.familysafety';
  static const microsoftFamilyWeb = 'https://family.microsoft.com';

  /// Download page for the Windows guard (host the signed installer here).
  static const windowsGuardDownload = 'https://zadx.app/windows';
}
