/// Paid tiers sold in the stores. The free plan has no tier: a `null` tier
/// (see [Entitlement.effectiveTier]) means "Free".
enum PlanTier { basic, plus }

enum BillingPeriod { monthly, yearly }

/// Every feature that a plan can include. The single source of truth for
/// "who gets what" is [featuresOf]; screens ask [hasFeature].
///
/// Names are mirrored in `backend/functions/src/security.ts` (`PLAN_FEATURES`)
/// and a test keeps both lists identical.
enum AppFeature {
  // ---- Free forever (owner decision 2026-11-21) ----
  /// Device lock: lock at prayer times + a simple daily time limit (1 child).
  appLock,

  /// Prayer times (the adhan needs them).
  prayerTimes,

  /// Adhan with every free muezzin voice.
  adhan,

  /// Quran reading + recitation with the approved reciters.
  quran,

  /// Adhkar section (free since owner decision 2026-11-21).
  adhkar,

  // ---- Basic (and Plus) ----
  /// Tasks, parent approval and the rewards wallet (play minutes).
  tasksRewards,

  /// Device games that unlock after tasks or on a timer.
  games,

  /// Built-in Zad X learning games.
  eduGames,

  /// Light exercises with animated figures.
  exercises,

  /// Parent-made tasks that unlock games.
  customUnlockTasks,

  /// More than one child profile (see [PlanPricing.maxChildren]).
  multipleChildren,

  /// Parent help assistant (daily cap on Basic).
  assistant,

  // ---- Plus only ----
  /// PlayStation Family and Microsoft Family Safety links + alerts.
  consoleLinks,

  /// Assistant with the high Plus daily cap.
  unlimitedAssistant,

  /// Weekly report for the parent.
  weeklyReport,
}

/// Free: the app lock, prayer times, adhan, Quran and adhkar.
const freeFeatures = <AppFeature>{
  AppFeature.appLock,
  AppFeature.prayerTimes,
  AppFeature.adhan,
  AppFeature.quran,
  AppFeature.adhkar,
};

/// Basic: everything in Free + the core paid features.
const basicFeatures = <AppFeature>{
  ...freeFeatures,
  AppFeature.tasksRewards,
  AppFeature.games,
  AppFeature.eduGames,
  AppFeature.exercises,
  AppFeature.customUnlockTasks,
  AppFeature.multipleChildren,
  AppFeature.assistant,
};

/// Plus: everything.
const plusFeatures = <AppFeature>{
  ...basicFeatures,
  AppFeature.consoleLinks,
  AppFeature.unlimitedAssistant,
  AppFeature.weeklyReport,
};

/// The feature set of a tier (`null` = Free).
Set<AppFeature> featuresOf(PlanTier? tier) => switch (tier) {
      null => freeFeatures,
      PlanTier.basic => basicFeatures,
      PlanTier.plus => plusFeatures,
    };

/// True when the family's current plan includes [feature].
/// Free features are always true, with or without login or purchase.
bool hasFeature(Entitlement entitlement, AppFeature feature) =>
    freeFeatures.contains(feature) || featuresOf(entitlement.effectiveTier).contains(feature);

/// The parent help assistant needs a plan the server verified (owner decision 2026-11-21).
///
/// The server (`askAssistant`) only knows store-verified plans, so during the on-device
/// 7-day trial it answers `subscription_required`. The app hides the assistant during that
/// trial too and shows "available after subscribing" instead, so both sides agree.
/// docs/decisions/FREE-ONE-CHILD.md
bool assistantAvailable(Entitlement entitlement) =>
    !entitlement.deviceTrial && hasFeature(entitlement, AppFeature.assistant);

/// Reads the tier string the server returns (`verifyPurchase`, family doc).
/// Anything unknown is Free, never silently Basic.
PlanTier? parsePlanTier(Object? value) => switch (value) {
      'basic' => PlanTier.basic,
      'plus' => PlanTier.plus,
      _ => null,
    };

/// Suggested list prices (USD) and limits. Real prices come from the store per country.
class PlanPricing {
  const PlanPricing({
    required this.tier,
    required this.monthly,
    required this.yearly,
    required this.maxGames,
    required this.maxChildren,
    required this.playStation,
    required this.unlimitedAssistant,
    required this.weeklyReport,
  });

  /// `null` for the Free plan.
  final PlanTier? tier;
  final double monthly;
  final double yearly;

  /// Games the parent can pick for the Games screen and the legacy "selected games" lock mode.
  /// In the default device-wide lock (`LockMode.allApps`) every non-allowed app is locked, so the
  /// plan cards no longer promise "N games" (owner decision 2026-11-21); the field is kept for
  /// the games picker.
  final int maxGames;
  final int maxChildren;
  final bool playStation;
  final bool unlimitedAssistant;
  final bool weeklyReport;

  bool get isFree => tier == null;
  Set<AppFeature> get features => featuresOf(tier);

  double get yearlyPerMonth => yearly / 12;
  int get yearlySavingPercent => monthly <= 0 ? 0 : (100 - yearly / (monthly * 12) * 100).round();
}

const planFree = PlanPricing(
  tier: null,
  monthly: 0,
  yearly: 0,
  maxGames: 0,
  maxChildren: 1,
  playStation: false,
  unlimitedAssistant: false,
  weeklyReport: false,
);

const planBasic = PlanPricing(
  tier: PlanTier.basic,
  monthly: 4.99,
  yearly: 39.99,
  maxGames: 5,
  maxChildren: 2,
  playStation: false,
  unlimitedAssistant: false,
  weeklyReport: false,
);

const planPlus = PlanPricing(
  tier: PlanTier.plus,
  monthly: 7.99,
  yearly: 59.99,
  maxGames: 15,
  maxChildren: 5,
  playStation: true,
  unlimitedAssistant: true,
  weeklyReport: true,
);

/// The three offers in display order: Free, Basic, Plus.
const allPlans = [planFree, planBasic, planPlus];

/// The pricing/limits for a tier (`null` = Free).
PlanPricing planFor(PlanTier? tier) => switch (tier) {
      null => planFree,
      PlanTier.basic => planBasic,
      PlanTier.plus => planPlus,
    };

/// What the family currently has access to.
class Entitlement {
  const Entitlement({
    this.tier,
    this.inTrial = false,
    this.expiresAt,
    this.now,
    this.trialDaysLeft,
    this.deviceTrial = false,
  });

  /// The tier the store/server reported (`null` = Free). A trial is a Plus
  /// tier with [inTrial] set.
  final PlanTier? tier;
  final bool inTrial;
  final DateTime? expiresAt;

  /// Whole days left in the on-device trial (1–7), or `null` when not in that trial.
  /// Shown in the parent area only.
  final int? trialDaysLeft;

  /// Clock override for tests.
  final DateTime Function()? now;

  /// True for the 7-day trial that runs on this device only ([resolveEntitlement] in
  /// trial_clock.dart). The server does not know about it, so server-checked features that
  /// cost money per use (the assistant) stay closed during it. A store trial verified by
  /// `verifyPurchase` is not a device trial.
  final bool deviceTrial;

  bool get isActive => tier != null && (expiresAt == null || expiresAt!.isAfter((now ?? DateTime.now)()));

  /// The tier in force right now: `null` (Free) once the plan expired.
  PlanTier? get effectiveTier => isActive ? tier : null;

  bool get isFree => effectiveTier == null;
  bool get isPlus => effectiveTier == PlanTier.plus;

  /// Limits of the plan in force. Free users get [planFree], never Basic.
  PlanPricing get limits => planFor(effectiveTier);
}
