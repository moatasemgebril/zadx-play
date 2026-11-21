import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/services/billing/entitlement_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final verifiedAt = DateTime.utc(2026, 11, 1, 12);
  final last = VerifiedEntitlement(tier: PlanTier.plus, verifiedAt: verifiedAt);

  group('EntitlementCache.resolve (pure)', () {
    test('fresh verification keeps the tier', () {
      expect(EntitlementCache.resolve(last: last, now: verifiedAt), PlanTier.plus);
    });

    test('day 6 is inside the grace period', () {
      final now = verifiedAt.add(const Duration(days: 6));
      expect(EntitlementCache.resolve(last: last, now: now), PlanTier.plus);
    });

    test('exactly 7 days is still inside the grace period', () {
      final now = verifiedAt.add(EntitlementCache.gracePeriod);
      expect(EntitlementCache.resolve(last: last, now: now), PlanTier.plus);
    });

    test('day 8 downgrades to free', () {
      final now = verifiedAt.add(const Duration(days: 8));
      expect(EntitlementCache.resolve(last: last, now: now), isNull);
    });

    test('clock rolled back before verifiedAt keeps the tier (elapsed = 0)', () {
      final now = verifiedAt.subtract(const Duration(days: 30));
      expect(EntitlementCache.resolve(last: last, now: now), PlanTier.plus);
    });

    test('clock rolled back after the grace was observed does not extend it', () {
      final rolledBack = verifiedAt.add(const Duration(days: 1));
      final seen = verifiedAt.add(const Duration(days: 8));
      expect(
        EntitlementCache.resolve(last: last, now: rolledBack, highWater: seen),
        isNull,
      );
    });

    test('never verified means free', () {
      expect(EntitlementCache.resolve(last: null, now: verifiedAt), isNull);
    });
  });

  group('EntitlementCache with SharedPreferences', () {
    late DateTime now;
    late EntitlementCache cache;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      now = verifiedAt;
      cache = EntitlementCache(prefs, clock: () => now);
    });

    test('never verified means free', () {
      expect(cache.lastVerified, isNull);
      expect(cache.effectiveTier(), isNull);
    });

    test('fresh, day 6 and day 8', () async {
      await cache.recordVerified(PlanTier.basic);
      expect(cache.lastVerified?.verifiedAt, verifiedAt);
      expect(cache.effectiveTier(), PlanTier.basic);

      now = verifiedAt.add(const Duration(days: 6));
      expect(cache.effectiveTier(), PlanTier.basic);

      now = verifiedAt.add(const Duration(days: 8));
      expect(cache.effectiveTier(), isNull);
    });

    test('rolling the clock back after day 8 does not restore the tier', () async {
      await cache.recordVerified(PlanTier.plus);
      now = verifiedAt.add(const Duration(days: 8));
      expect(cache.effectiveTier(), isNull);

      now = verifiedAt.add(const Duration(days: 2));
      expect(cache.effectiveTier(), isNull);
      expect(cache.highWaterMark, verifiedAt.add(const Duration(days: 8)));
    });

    test('rolling the clock back before verifiedAt does not extend the grace', () async {
      await cache.recordVerified(PlanTier.plus);
      now = verifiedAt.add(const Duration(days: 5));
      expect(cache.effectiveTier(), PlanTier.plus);

      now = verifiedAt.subtract(const Duration(days: 10));
      expect(cache.effectiveTier(), PlanTier.plus);

      // Real time moves on 3 more days: grace ends on day 8 as seen before the rollback.
      now = verifiedAt.add(const Duration(days: 8));
      expect(cache.effectiveTier(), isNull);
    });

    test('a new verification resets the grace and a wrong future clock', () async {
      await cache.recordVerified(PlanTier.plus);
      now = verifiedAt.add(const Duration(days: 365));
      expect(cache.effectiveTier(), isNull);

      now = verifiedAt.add(const Duration(days: 9));
      await cache.recordVerified(PlanTier.plus);
      expect(cache.effectiveTier(), PlanTier.plus);
    });

    test('server says free clears the cached tier', () async {
      await cache.recordVerified(PlanTier.plus);
      await cache.recordVerified(null);
      expect(cache.lastVerified, isNull);
      expect(cache.effectiveTier(), isNull);
    });
  });
}
