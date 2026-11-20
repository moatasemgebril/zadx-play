/// Single place for brand and business constants.
///
/// Store listing name approved: "Zad X Play". Parent keywords go in the
/// subtitle (see [storeSubtitleAr]), not in the name.
class AppConfig {
  const AppConfig._();

  /// Brand name shown inside the app (logo, titles).
  static const brandName = 'Zad X';

  /// Name used for the store listing / launcher label.
  /// Keep in sync with android:label and CFBundleDisplayName.
  static const storeName = 'Zad X Play';

  /// App Store subtitle / Google Play short description.
  static const storeSubtitleAr = 'ألعاب بعد الصلاة والمهام';
  static const storeSubtitleEn = 'Games after prayer & tasks';

  static const androidPackage = 'com.zadx.app';
  static const iosBundleId = 'com.zadx.app';

  /// Shared container used by the iOS app + extensions (App Group).
  static const iosAppGroup = 'group.com.zadx.app';

  // Subscription product ids (must match App Store Connect / Play Console).
  static const productBasicMonthly = 'zadx_basic_monthly';
  static const productBasicYearly = 'zadx_basic_yearly';
  static const productPlusMonthly = 'zadx_plus_monthly';
  static const productPlusYearly = 'zadx_plus_yearly';

  static const Set<String> allProductIds = {
    productBasicMonthly,
    productBasicYearly,
    productPlusMonthly,
    productPlusYearly,
  };

  /// Free trial length offered on both plans (configured in the stores).
  static const trialDays = 14;

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
