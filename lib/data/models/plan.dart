enum PlanTier { basic, plus }

enum BillingPeriod { monthly, yearly }

/// Suggested list prices (USD). Real prices come from the store per country.
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

  final PlanTier tier;
  final double monthly;
  final double yearly;
  final int maxGames;
  final int maxChildren;
  final bool playStation;
  final bool unlimitedAssistant;
  final bool weeklyReport;

  double get yearlyPerMonth => yearly / 12;
  int get yearlySavingPercent => (100 - yearly / (monthly * 12) * 100).round();
}

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

/// What the family currently has access to.
class Entitlement {
  const Entitlement({this.tier, this.inTrial = false, this.expiresAt});

  final PlanTier? tier;
  final bool inTrial;
  final DateTime? expiresAt;

  bool get isPlus => tier == PlanTier.plus;
  bool get isActive => tier != null && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));

  PlanPricing get limits => isPlus ? planPlus : planBasic;
}
