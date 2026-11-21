import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/plan.dart';
import '../../features/settings/settings_controller.dart';

/// Returns the current wall-clock time. Injected so tests can move time.
typedef Clock = DateTime Function();

/// The last entitlement the server confirmed (`verifyPurchase` or the
/// server-written family doc). Never built from an unverified client value.
class VerifiedEntitlement {
  const VerifiedEntitlement({required this.tier, required this.verifiedAt});

  final PlanTier tier;

  /// When the server confirmed [tier], in UTC (device clock at that moment).
  final DateTime verifiedAt;
}

/// Offline grace period for a paid plan.
///
/// The app keeps the last VERIFIED tier for [gracePeriod] after the last
/// successful server check, so a family without internet keeps what it paid
/// for. After that the effective tier falls back to free (`null`) until the
/// next successful verification.
///
/// Clock-rollback safety (documented choice):
/// * Every time the cache is read it remembers the latest time it has seen
///   (the "high-water mark"). Elapsed time is measured from [VerifiedEntitlement.verifiedAt]
///   to `max(now, highWater)`, so moving the device clock back never makes the
///   grace period longer than what was already observed.
/// * If the clock is before `verifiedAt` (rolled back before the check), the
///   elapsed time is treated as 0 (`max(0, …)`): the tier is kept, but the
///   grace never ends later than `verifiedAt + gracePeriod` as measured by the
///   high-water mark.
/// * A successful server verification resets the high-water mark to the
///   verification time, so a clock that was once wrong in the future cannot
///   lock an honest family out forever.
/// * Residual risk (accepted): a clock frozen in the past *before* the grace
///   ran out keeps the tier until the device next goes online. Paid tiers only
///   change limits (number of games/children, extras); they never lift a lock,
///   so this cannot weaken child safety. A downgrade also never unlocks games.
class EntitlementCache {
  EntitlementCache(this._prefs, {Clock? clock}) : _clock = clock ?? DateTime.now;

  static const gracePeriod = Duration(days: 7);

  static const _kTier = 'billing.verified.tier';
  static const _kVerifiedAt = 'billing.verified.atMs';
  static const _kHighWater = 'billing.clock.highWaterMs';

  final SharedPreferences _prefs;
  final Clock _clock;

  /// Pure decision: the tier in force at [now], given the last verification
  /// and the latest time ever observed ([highWater]). `null` = free.
  static PlanTier? resolve({
    required VerifiedEntitlement? last,
    required DateTime now,
    DateTime? highWater,
  }) {
    if (last == null) return null;
    final nowUtc = now.toUtc();
    final reference = (highWater != null && highWater.isAfter(nowUtc)) ? highWater.toUtc() : nowUtc;
    var elapsed = reference.difference(last.verifiedAt.toUtc());
    if (elapsed.isNegative) elapsed = Duration.zero;
    return elapsed <= gracePeriod ? last.tier : null;
  }

  /// The stored last verification, or `null` if the server never confirmed a
  /// paid tier (or confirmed free).
  VerifiedEntitlement? get lastVerified {
    final tier = PlanTier.values.asNameMap()[_prefs.getString(_kTier)];
    final ms = _prefs.getInt(_kVerifiedAt);
    if (tier == null || ms == null) return null;
    return VerifiedEntitlement(tier: tier, verifiedAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
  }

  DateTime? get highWaterMark {
    final ms = _prefs.getInt(_kHighWater);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// Effective tier now. Also advances the high-water mark (never moves it back).
  PlanTier? effectiveTier() {
    final now = _clock().toUtc();
    final previous = highWaterMark;
    final highWater = (previous == null || now.isAfter(previous)) ? now : previous;
    if (highWater != previous) {
      unawaited(_prefs.setInt(_kHighWater, highWater.millisecondsSinceEpoch));
    }
    return resolve(last: lastVerified, now: now, highWater: highWater);
  }

  /// Call after the server confirmed the family's plan. `null` = free / expired,
  /// which clears the cached tier.
  Future<void> recordVerified(PlanTier? tier) async {
    final now = _clock().toUtc();
    if (tier == null) {
      await _prefs.remove(_kTier);
      await _prefs.remove(_kVerifiedAt);
    } else {
      await _prefs.setString(_kTier, tier.name);
      await _prefs.setInt(_kVerifiedAt, now.millisecondsSinceEpoch);
    }
    await _prefs.setInt(_kHighWater, now.millisecondsSinceEpoch);
  }
}

/// Not wired into `entitlementProvider` yet (see BACKLOG.md "Offline-first"):
/// the provider still defaults to a Plus trial (risk R-16), which is a product
/// decision to settle first.
final entitlementCacheProvider = Provider<EntitlementCache>(
  (ref) => EntitlementCache(ref.watch(sharedPrefsProvider)),
);
