import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/services/billing/entitlement_cache.dart';
import 'package:zadx/services/billing/subscription_service.dart';
import 'package:zadx/services/billing/trial_clock.dart';
import 'package:zadx/services/family/family_repository.dart';
import 'package:zadx/services/family/pairing_service.dart';

/// P0-A: the plan a parent bought (stored on families/{id} by `verifyPurchase`) must reach a
/// child device that has no purchase of its own, through the 7-day offline grace cache.
class _FamilyDocRepository extends LocalFamilyRepository {
  final controller = StreamController<Entitlement>.broadcast();

  @override
  Stream<Entitlement> watchEntitlement() => controller.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime.utc(2026, 11, 21, 9);
  late DateTime now;
  DateTime clock() => now;

  Map<String, dynamic> doc(String? plan, Duration expiresIn) => {
        'plan': plan,
        'planExpiresAt': t0.add(expiresIn).toIso8601String(),
        'inTrial': false,
        'members': ['parent', 'child-phone'],
      };

  group('parseFamilyEntitlement (fields written by verifyPurchase)', () {
    Entitlement parse(Map<String, dynamic> d) => parseFamilyEntitlement(d, now: () => t0);

    test('active plus / basic', () {
      expect(parse(doc('plus', const Duration(days: 20))).effectiveTier, PlanTier.plus);
      expect(parse(doc('basic', const Duration(days: 20))).effectiveTier, PlanTier.basic);
    });

    test('expired plan is Free', () {
      expect(parse(doc('plus', const Duration(minutes: -1))).isFree, isTrue);
    });

    test('fails closed: unknown plan, missing or bad expiry', () {
      expect(parse(doc('gold', const Duration(days: 20))).isFree, isTrue);
      expect(parse({'plan': 'plus'}).isFree, isTrue);
      expect(parse({'plan': 'plus', 'planExpiresAt': 'soon'}).isFree, isTrue);
      expect(parse({'plan': 'plus', 'planExpiresAt': 12345}).isFree, isTrue);
      expect(parse(const {}).isFree, isTrue);
    });

    test('accepts a DateTime expiry (Firestore Timestamp converted by the repository)', () {
      final e = parse({'plan': 'basic', 'planExpiresAt': t0.add(const Duration(days: 3)), 'inTrial': true});
      expect(e.effectiveTier, PlanTier.basic);
      expect(e.inTrial, isTrue);
    });
  });

  group('resolveEntitlement with the family plan', () {
    final ended = TrialClock.resolve(startedAt: t0.subtract(const Duration(days: 10)), now: t0);
    final active = TrialClock.resolve(startedAt: t0, now: t0);
    Entitlement fam(String plan, Duration expiresIn) => parseFamilyEntitlement(doc(plan, expiresIn), now: () => t0);

    test('child device with no purchase gets the family tier', () {
      expect(resolveEntitlement(family: fam('plus', const Duration(days: 5)), trial: ended).effectiveTier, PlanTier.plus);
      expect(resolveEntitlement(family: fam('basic', const Duration(days: 5)), trial: ended).effectiveTier, PlanTier.basic);
    });

    test('highest active tier wins between this device and the family', () {
      final basicHere = Entitlement(tier: PlanTier.basic, expiresAt: t0.add(const Duration(days: 5)), now: () => t0);
      final plusFamily = fam('plus', const Duration(days: 5));
      expect(resolveEntitlement(store: basicHere, family: plusFamily, trial: ended).effectiveTier, PlanTier.plus);
      expect(resolveEntitlement(store: plusFamily, family: fam('basic', const Duration(days: 5)), trial: ended).effectiveTier,
          PlanTier.plus);
      // An expired family plan never hides this device's active purchase.
      expect(resolveEntitlement(store: basicHere, family: fam('plus', const Duration(days: -1)), trial: ended).effectiveTier,
          PlanTier.basic);
    });

    test('expired family plan: trial while it runs, then Free', () {
      final expired = fam('plus', const Duration(days: -1));
      expect(resolveEntitlement(family: expired, trial: active).inTrial, isTrue);
      expect(resolveEntitlement(family: expired, trial: ended).isFree, isTrue);
    });
  });

  group('planEntitlementProvider on a child device (no purchase of its own)', () {
    late SharedPreferences prefs;

    ProviderContainer container(_FamilyDocRepository repo) {
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        entitlementCacheProvider.overrideWithValue(EntitlementCache(prefs, clock: clock)),
        trialClockProvider.overrideWithValue(TrialClock(prefs, clock: clock)),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        storeEntitlementProvider.overrideWith((ref) => Stream.value(null)),
        familyRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      c.listen(planEntitlementProvider, (_, __) {});
      return c;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() async {
      now = t0;
      // The device's own 7-day trial ended long ago.
      SharedPreferences.setMockInitialValues({
        'billing.trial.startedAtMs': t0.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('family doc says plus (active) -> Plus; basic -> Basic', () async {
      final repo = _FamilyDocRepository();
      final c = container(repo);
      await settle();
      expect(c.read(planEntitlementProvider).isFree, isTrue);

      repo.controller.add(parseFamilyEntitlement(doc('plus', const Duration(days: 20)), now: clock));
      await settle();
      expect(c.read(planEntitlementProvider).effectiveTier, PlanTier.plus);
      expect(EntitlementCache(prefs, clock: clock).lastVerified?.tier, PlanTier.plus);

      repo.controller.add(parseFamilyEntitlement(doc('basic', const Duration(days: 20)), now: clock));
      await settle();
      expect(c.read(planEntitlementProvider).effectiveTier, PlanTier.basic);
    });

    test('family doc says expired -> Free (and the cached tier is cleared)', () async {
      final repo = _FamilyDocRepository();
      final c = container(repo);
      repo.controller.add(parseFamilyEntitlement(doc('plus', const Duration(days: 20)), now: clock));
      await settle();
      expect(c.read(planEntitlementProvider).isPlus, isTrue);

      repo.controller.add(parseFamilyEntitlement(doc('plus', const Duration(days: -1)), now: clock));
      await settle();
      expect(c.read(planEntitlementProvider).isFree, isTrue);
      expect(EntitlementCache(prefs, clock: clock).lastVerified, isNull);
    });

    test('offline: the last family plan is kept for the 7-day grace, then Free', () async {
      final online = _FamilyDocRepository();
      container(online);
      online.controller.add(parseFamilyEntitlement(doc('plus', const Duration(days: 30)), now: clock));
      await settle();

      // Next launches: no server snapshot arrives (offline).
      now = t0.add(const Duration(days: 3));
      var c = container(_FamilyDocRepository());
      await settle();
      expect(c.read(planEntitlementProvider).effectiveTier, PlanTier.plus);

      now = t0.add(const Duration(days: 8));
      c = container(_FamilyDocRepository());
      await settle();
      expect(c.read(planEntitlementProvider).isFree, isTrue);
    });

    test('offline grace is not stretched by turning the clock back', () async {
      final online = _FamilyDocRepository();
      container(online);
      online.controller.add(parseFamilyEntitlement(doc('basic', const Duration(days: 30)), now: clock));
      await settle();

      now = t0.add(const Duration(days: 8));
      container(_FamilyDocRepository());
      await settle();
      now = t0.add(const Duration(days: 2)); // rolled back
      final c = container(_FamilyDocRepository());
      await settle();
      expect(c.read(planEntitlementProvider).isFree, isTrue);
    });
  });

  test('a subscription of another family is recognised (no auto-join, parent code instead)', () {
    expect(isPurchaseInOtherFamily('purchase_in_other_family'), isTrue);
    expect(isPurchaseInOtherFamily('purchase_in_use'), isFalse);
    expect(isPurchaseInOtherFamily(null), isFalse);
  });

  test('a redeemed family id must be a well-formed Firestore id', () {
    expect(isSafeFamilyId('Fam_123-x'), isTrue);
    expect(isSafeFamilyId('../x'), isFalse);
    expect(isSafeFamilyId(''), isFalse);
    expect(isSafeFamilyId('a/b'), isFalse);
  });
}
