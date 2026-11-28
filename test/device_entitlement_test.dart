// Owner decision 2026-11-28 (zero cost, Firebase Spark, no Cloud Functions): the plan comes from
// the store's purchase state on the device that bought it, the purchase is acknowledged on the
// device, and the existing 7-day offline grace still applies. No server receipt check.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/core/app_config.dart';
import 'package:zadx/core/server_functions.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/services/billing/device_entitlement.dart';
import 'package:zadx/services/billing/entitlement_cache.dart';
import 'package:zadx/services/billing/subscription_service.dart';
import 'package:zadx/services/billing/trial_clock.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/children_controller.dart';
import 'package:zadx/services/family/family_repository.dart';

/// Records acknowledgements; any other store call is unexpected here.
class _FakeIap implements InAppPurchase {
  final completed = <String>[];

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async => completed.add(purchase.productID);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Spark gateway, counting every attempted Cloud Functions call.
class _CountingServer extends ServerCalls {
  int calls = 0;

  @override
  bool get enabled => false;

  @override
  Future<Object?> call(String name, [Map<String, Object?>? data, Duration? timeout]) {
    calls++;
    return Future<Object?>.error(ServerFunctionsDisabled(name));
  }
}

class _SharingRepo extends LocalFamilyRepository {
  final shared = <Entitlement>[];

  @override
  Future<void> shareFamilyPlan(Entitlement plan) async => shared.add(plan);
}

PurchaseDetails _purchase(
  String productId, {
  PurchaseStatus status = PurchaseStatus.restored,
  DateTime? date,
  bool pendingAck = false,
}) =>
    PurchaseDetails(
      productID: productId,
      verificationData: PurchaseVerificationData(localVerificationData: '', serverVerificationData: 'token', source: 'test'),
      transactionDate: date?.millisecondsSinceEpoch.toString(),
      status: status,
    )..pendingCompletePurchase = pendingAck;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Real "now": Entitlement.isActive compares with the real clock.
  final t0 = DateTime.now().toUtc();

  group('pure rules', () {
    test('product ids map to tier and period; anything else grants nothing', () {
      expect(productPlan(AppConfig.productBasicMonthly), (PlanTier.basic, BillingPeriod.monthly));
      expect(productPlan(AppConfig.productBasicYearly), (PlanTier.basic, BillingPeriod.yearly));
      expect(productPlan(AppConfig.productPlusMonthly), (PlanTier.plus, BillingPeriod.monthly));
      expect(productPlan(AppConfig.productPlusYearly), (PlanTier.plus, BillingPeriod.yearly));
      expect(productPlan('some_other_app_product'), isNull);
      expect(deviceEntitlementFor(productId: 'nope', googlePlay: true, now: t0), isNull);
    });

    test('Google Play: an active purchase grants its tier for the 7-day grace from now (rolling)', () {
      final e = deviceEntitlementFor(productId: AppConfig.productPlusMonthly, googlePlay: true, now: t0)!;
      expect(e.tier, PlanTier.plus);
      expect(e.inTrial, isFalse);
      expect(e.expiresAt, t0.add(EntitlementCache.gracePeriod));
    });

    test('App Store: one billing period after the transaction (+1 day); an old transaction is expired', () {
      final recent = deviceEntitlementFor(
        productId: AppConfig.productBasicMonthly,
        googlePlay: false,
        now: t0,
        transactionDate: t0.subtract(const Duration(days: 10)),
      )!;
      expect(recent.effectiveTier, PlanTier.basic);
      expect(recent.expiresAt, t0.subtract(const Duration(days: 10)).add(const Duration(days: 32)));

      final old = deviceEntitlementFor(
        productId: AppConfig.productBasicMonthly,
        googlePlay: false,
        now: t0,
        transactionDate: t0.subtract(const Duration(days: 40)),
      )!;
      expect(old.isFree, isTrue);

      final yearly = deviceEntitlementFor(
        productId: AppConfig.productPlusYearly,
        googlePlay: false,
        now: t0,
        transactionDate: t0.subtract(const Duration(days: 300)),
      )!;
      expect(yearly.effectiveTier, PlanTier.plus);
    });

    test('App Store: no transaction date, no plan (fails closed)', () {
      expect(deviceEntitlementFor(productId: AppConfig.productPlusYearly, googlePlay: false, now: t0), isNull);
    });

    test('transaction dates: milliseconds string only', () {
      expect(parseTransactionDate('1700000000000'), DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true));
      expect(parseTransactionDate(null), isNull);
      expect(parseTransactionDate(''), isNull);
      expect(parseTransactionDate('yesterday'), isNull);
    });

    test('best of several purchases: highest active tier', () {
      final basic = Entitlement(tier: PlanTier.basic, expiresAt: t0.add(const Duration(days: 30)));
      final plus = Entitlement(tier: PlanTier.plus, expiresAt: t0.add(const Duration(days: 3)));
      final expiredPlus = Entitlement(tier: PlanTier.plus, expiresAt: t0.subtract(const Duration(days: 1)));
      expect(bestDeviceEntitlement([basic, plus], t0), same(plus));
      expect(bestDeviceEntitlement([expiredPlus, basic], t0), same(basic));
      expect(bestDeviceEntitlement([expiredPlus], t0), isNull);
      expect(bestDeviceEntitlement(const [], t0), isNull);
    });
  });

  group('SubscriptionService (zero-cost flow)', () {
    late _FakeIap iap;
    late _CountingServer server;
    late SubscriptionService service;

    setUp(() {
      iap = _FakeIap();
      server = _CountingServer();
      service = SubscriptionService(iap: iap, server: server, clock: () => t0, platform: TargetPlatform.android);
      addTearDown(service.dispose);
    });

    test('a purchase grants the plan on this device and is acknowledged; no Cloud Function call', () async {
      final seen = <Entitlement>[];
      service.entitlementStream.listen(seen.add);
      await service.handlePurchases([_purchase(AppConfig.productPlusYearly, status: PurchaseStatus.purchased, pendingAck: true)]);
      await Future<void>.delayed(Duration.zero);
      expect(service.latest?.effectiveTier, PlanTier.plus);
      expect(seen.single.effectiveTier, PlanTier.plus);
      expect(iap.completed, [AppConfig.productPlusYearly]);
      expect(server.calls, 0);
    });

    test('pending, cancelled and failed purchases grant nothing', () async {
      await service.handlePurchases([
        _purchase(AppConfig.productPlusMonthly, status: PurchaseStatus.pending),
        _purchase(AppConfig.productPlusMonthly, status: PurchaseStatus.canceled),
        _purchase(AppConfig.productPlusMonthly, status: PurchaseStatus.error),
      ]);
      expect(service.latest, isNull);
      expect(server.calls, 0);
    });

    test('an unknown product grants nothing but is still acknowledged', () async {
      await service.handlePurchases([_purchase('other_product', pendingAck: true)]);
      expect(service.latest, isNull);
      expect(iap.completed, ['other_product']);
    });

    test('Basic + Plus restored together: Plus', () async {
      await service.handlePurchases([_purchase(AppConfig.productBasicMonthly), _purchase(AppConfig.productPlusMonthly)]);
      expect(service.latest?.effectiveTier, PlanTier.plus);
    });

    test('App Store restore: an expired old transaction does not unlock', () async {
      final ios = SubscriptionService(iap: iap, server: server, clock: () => t0, platform: TargetPlatform.iOS);
      addTearDown(ios.dispose);
      await ios.handlePurchases([_purchase(AppConfig.productPlusMonthly, date: t0.subtract(const Duration(days: 90)))]);
      expect(ios.latest, isNull);
      await ios.handlePurchases([_purchase(AppConfig.productPlusMonthly, date: t0.subtract(const Duration(days: 5)))]);
      expect(ios.latest?.effectiveTier, PlanTier.plus);
    });
  });

  group('plan on this device + 7-day offline grace', () {
    late SharedPreferences prefs;
    late DateTime now;
    DateTime clock() => now;

    ProviderContainer launch(SubscriptionService service, {FamilyRepository? repo}) {
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        entitlementCacheProvider.overrideWithValue(EntitlementCache(prefs, clock: clock)),
        trialClockProvider.overrideWithValue(TrialClock(prefs, clock: clock)),
        clockProvider.overrideWith((ref) => Stream.value(now)),
        subscriptionServiceProvider.overrideWithValue(service),
        familyRepositoryProvider.overrideWithValue(repo ?? LocalFamilyRepository()),
      ]);
      addTearDown(c.dispose);
      c.listen(planEntitlementProvider, (_, __) {});
      return c;
    }

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    setUp(() async {
      now = t0;
      SharedPreferences.setMockInitialValues({
        // The device's own 7-day trial ended long ago.
        'billing.trial.startedAtMs': t0.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('store purchase -> Plus; next launches offline keep it 7 days, then Free', () async {
      final online = SubscriptionService(iap: _FakeIap(), server: _CountingServer(), clock: clock, platform: TargetPlatform.android);
      final first = launch(online);
      await settle();
      expect(first.read(planEntitlementProvider).isFree, isTrue);

      await online.handlePurchases([_purchase(AppConfig.productPlusMonthly)]);
      await settle();
      expect(first.read(planEntitlementProvider).effectiveTier, PlanTier.plus);
      await settle();
      expect(EntitlementCache(prefs, clock: clock).lastVerified?.tier, PlanTier.plus);

      // Six days later, offline: the store has not answered (no restore yet).
      now = t0.add(const Duration(days: 6));
      final offline = launch(SubscriptionService(iap: _FakeIap(), server: _CountingServer(), clock: clock));
      await settle();
      expect(offline.read(planEntitlementProvider).effectiveTier, PlanTier.plus);

      // Eight days later, still offline: the grace is over.
      now = t0.add(const Duration(days: 8));
      final later = launch(SubscriptionService(iap: _FakeIap(), server: _CountingServer(), clock: clock));
      await settle();
      expect(later.read(planEntitlementProvider).isFree, isTrue);
    });

    test('a parent phone shares the store plan with the family doc', () async {
      final repo = _SharingRepo();
      final service = SubscriptionService(iap: _FakeIap(), server: _CountingServer(), clock: clock, platform: TargetPlatform.android);
      final c = launch(service, repo: repo);
      c.listen(familyPlanSharerProvider, (_, __) {});
      await service.handlePurchases([_purchase(AppConfig.productBasicYearly)]);
      await settle();
      expect(repo.shared.single.effectiveTier, PlanTier.basic);
      expect(repo.shared.single.expiresAt, isNotNull);
    });

    test('a paired child device never writes the family plan', () async {
      SharedPreferences.setMockInitialValues({
        'billing.trial.startedAtMs': t0.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
        ChildStorage.boundKey: ChildProfile.defaultId,
      });
      prefs = await SharedPreferences.getInstance();
      final repo = _SharingRepo();
      final service = SubscriptionService(iap: _FakeIap(), server: _CountingServer(), clock: clock, platform: TargetPlatform.android);
      final c = launch(service, repo: repo);
      expect(c.read(childrenProvider).isBound, isTrue);
      c.listen(familyPlanSharerProvider, (_, __) {});
      await service.handlePurchases([_purchase(AppConfig.productPlusYearly)]);
      await settle();
      expect(repo.shared, isEmpty);
      // The device itself still gets the plan it bought.
      expect(c.read(planEntitlementProvider).effectiveTier, PlanTier.plus);
    });
  });
}
