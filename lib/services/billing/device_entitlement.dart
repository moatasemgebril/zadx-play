import '../../core/app_config.dart';
import '../../data/models/plan.dart';
import 'entitlement_cache.dart';

// On-device entitlement (owner decision 2026-11-28: zero cost, no Cloud Functions, so no
// server receipt check). The store's purchase state on the device that bought the plan is
// trusted:
//
// * Google Play: a restore (`queryPurchasesAsync`, run on every Android launch) returns only
//   subscriptions that are active now, and Play signs them on the device. The plan is valid for
//   [EntitlementCache.gracePeriod] after the store last confirmed it (rolling), so a cancelled
//   subscription ends at most 7 days after the last launch that still saw it.
// * App Store (iOS / macOS): every transaction carries its purchase date. The plan is valid for
//   one billing period after the latest transaction ([storePeriodLength] + one day of
//   billing-retry margin), so an old, expired transaction returned by a restore never unlocks.
//
// Accepted weaker anti-fraud (docs/decisions/SPARK-APP-NO-FUNCTIONS.md): a rooted / jailbroken device
// can fake its own store answer. Paid tiers only add features and children; they never lift a
// lock, so this cannot weaken child safety.

/// Tier and billing period of one of this app's store products; null for any other id.
(PlanTier, BillingPeriod)? productPlan(String productId) => switch (productId) {
      AppConfig.productBasicMonthly => (PlanTier.basic, BillingPeriod.monthly),
      AppConfig.productBasicYearly => (PlanTier.basic, BillingPeriod.yearly),
      AppConfig.productPlusMonthly => (PlanTier.plus, BillingPeriod.monthly),
      AppConfig.productPlusYearly => (PlanTier.plus, BillingPeriod.yearly),
      _ => null,
    };

/// Length of one App Store billing period (rounded up: the longest month, a leap year).
Duration storePeriodLength(BillingPeriod period) => switch (period) {
      BillingPeriod.monthly => const Duration(days: 31),
      BillingPeriod.yearly => const Duration(days: 366),
    };

/// Margin after an App Store period for the store's billing retry / renewal delivery.
const appStoreRenewalMargin = Duration(days: 1);

/// The store's purchase date (`PurchaseDetails.transactionDate`: milliseconds since epoch as a
/// string). Null when missing or unreadable.
DateTime? parseTransactionDate(String? raw) {
  final ms = int.tryParse(raw ?? '');
  return ms == null || ms <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// The plan one store purchase on this device grants at [now], or null when it grants nothing
/// (unknown product, or an App Store transaction without a date).
Entitlement? deviceEntitlementFor({
  required String productId,
  required bool googlePlay,
  required DateTime now,
  DateTime? transactionDate,
}) {
  final plan = productPlan(productId);
  if (plan == null) return null;
  final (tier, period) = plan;
  final DateTime expiresAt;
  if (googlePlay) {
    expiresAt = now.toUtc().add(EntitlementCache.gracePeriod);
  } else {
    if (transactionDate == null) return null;
    expiresAt = transactionDate.toUtc().add(storePeriodLength(period)).add(appStoreRenewalMargin);
  }
  return Entitlement(tier: tier, expiresAt: expiresAt);
}

int _rank(PlanTier? tier) => switch (tier) { PlanTier.plus => 2, PlanTier.basic => 1, null => 0 };

/// The best of several device purchases: the highest tier still active at [now], then the latest
/// expiry. Null when none is active.
Entitlement? bestDeviceEntitlement(Iterable<Entitlement> all, DateTime now) {
  Entitlement? best;
  for (final e in all) {
    final active = Entitlement(tier: e.tier, expiresAt: e.expiresAt, now: () => now);
    if (active.isFree) continue;
    if (best == null) {
      best = e;
      continue;
    }
    final r = _rank(active.effectiveTier);
    final rb = _rank(best.tier);
    final later = (e.expiresAt ?? now).isAfter(best.expiresAt ?? now);
    if (r > rb || (r == rb && later)) best = e;
  }
  return best;
}
