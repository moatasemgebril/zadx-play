import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/app_config.dart';
import '../../core/feature_flags.dart';
import '../../core/server_functions.dart';
import '../../data/models/plan.dart';
import '../../features/prayer/prayer_providers.dart';
import '../family/children_controller.dart';
import '../family/family_repository.dart';
import 'device_entitlement.dart';
import 'entitlement_cache.dart';
import 'trial_clock.dart';

/// Store subscriptions (App Store / Google Play).
///
/// Zero-cost flow (default, owner decision 2026-11-28, [FeatureFlags.serverFunctions] off):
/// buy() → store sheet → purchaseStream → the plan is read from the store's purchase state on
/// THIS device ([deviceEntitlementFor]) → [entitlementProvider] updates. The purchase is
/// acknowledged / finished on the device ([InAppPurchase.completePurchase]; Google Play refunds a
/// purchase that is not acknowledged within 3 days). A parent phone then shares the plan with
/// the family doc ([familyPlanSharerProvider]) so the child devices get it.
///
/// Blaze flow (flag on): the `verifyPurchase` Cloud Function validates the receipt, stores the
/// entitlement in Firestore and credits the referrer if a referral code was used.
class SubscriptionService {
  SubscriptionService({InAppPurchase? iap, ServerCalls? server, DateTime Function()? clock, TargetPlatform? platform})
      : _iapOverride = iap,
        _server = server ?? serverCallsFor(),
        _clock = clock ?? DateTime.now,
        _platform = platform;

  final InAppPurchase? _iapOverride;
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;
  final ServerCalls _server;
  final DateTime Function() _clock;
  final TargetPlatform? _platform;
  TargetPlatform get _targetPlatform => _platform ?? defaultTargetPlatform;

  /// Plans this device's store confirmed in this session, per product (zero-cost flow).
  final Map<String, Entitlement> _devicePurchases = {};
  final _entitlement = StreamController<Entitlement>.broadcast();
  final _otherFamily = StreamController<bool>.broadcast();
  bool _inOtherFamily = false;

  /// True after `verifyPurchase` refused this store subscription because it belongs to another
  /// Zad X family (e.g. restore on a new phone). The server never joins or unlocks the family
  /// for it; the parent links this phone with a parent code from an existing parent phone.
  bool get inOtherFamily => _inOtherFamily;
  Stream<bool> get inOtherFamilyStream => _otherFamily.stream;

  void _setInOtherFamily(bool value) {
    if (_inOtherFamily == value) return;
    _inOtherFamily = value;
    _otherFamily.add(value);
  }
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Map<String, ProductDetails> _products = {};
  String? _pendingReferralCode;

  Entitlement? _latest;

  Stream<Entitlement> get entitlementStream => _entitlement.stream;

  /// The last plan this device's store (or `verifyPurchase` on Blaze) confirmed in this session
  /// (events sent before anyone listened are not lost).
  Entitlement? get latest => _latest;
  Map<String, ProductDetails> get products => _products;

  Future<void> init() async {
    if (!await _iap.isAvailable()) return;
    final response = await _iap.queryProductDetails(AppConfig.allProductIds);
    _products = {for (final p in response.productDetails) p.id: p};
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => debugPrint('IAP error: $e'));
    // Google Play answers a restore silently (no sign-in prompt), so a paying family is
    // re-verified on every launch. iOS delivers renewals by itself; the parent can also tap
    // "Restore purchases" (an automatic restore could prompt for the Apple ID password).
    if (_targetPlatform == TargetPlatform.android) {
      await _iap.restorePurchases();
    }
  }

  static String productId(PlanTier tier, BillingPeriod period) => switch ((tier, period)) {
        (PlanTier.basic, BillingPeriod.monthly) => AppConfig.productBasicMonthly,
        (PlanTier.basic, BillingPeriod.yearly) => AppConfig.productBasicYearly,
        (PlanTier.plus, BillingPeriod.monthly) => AppConfig.productPlusMonthly,
        (PlanTier.plus, BillingPeriod.yearly) => AppConfig.productPlusYearly,
      };

  /// Localized store price, e.g. "EGP 149.99", falling back to the suggested USD price.
  String? storePrice(PlanTier tier, BillingPeriod period) => _products[productId(tier, period)]?.price;

  Future<bool> buy(PlanTier tier, BillingPeriod period, {String? referralCode}) async {
    final product = _products[productId(tier, period)];
    if (product == null) return false;
    _pendingReferralCode = referralCode;
    return _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) => handlePurchases(purchases);

  /// Grants the plan of every purchased / restored store purchase, then acknowledges it.
  /// Pending (e.g. a cash payment not made yet), cancelled and failed purchases grant nothing.
  @visibleForTesting
  Future<void> handlePurchases(List<PurchaseDetails> purchases) async {
    var deviceChanged = false;
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        if (_server.enabled) {
          await _verifyOnServer(p);
        } else {
          deviceChanged = _grantOnDevice(p) || deviceChanged;
        }
      }
      // Acknowledge (Google Play) / finish (App Store) on the device: Play refunds a purchase that
      // is not acknowledged within 3 days. A failed acknowledgement is retried by the next launch's
      // restore (Play reports the purchase again with pendingCompletePurchase set).
      if (p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (e) {
          debugPrint('completePurchase failed: $e');
        }
      }
    }
    if (deviceChanged) {
      final best = bestDeviceEntitlement(_devicePurchases.values, _clock());
      if (best != null) {
        _latest = best;
        _entitlement.add(best);
      }
    }
  }

  /// Zero-cost flow: trusts the store's purchase state on this device. True when it granted or
  /// extended a plan.
  bool _grantOnDevice(PurchaseDetails p) {
    final now = _clock();
    var date = parseTransactionDate(p.transactionDate);
    // A purchase made right now may arrive before the store filled in its date.
    if (date == null && p.status == PurchaseStatus.purchased) date = now.toUtc();
    final ent = deviceEntitlementFor(
      productId: p.productID,
      googlePlay: _targetPlatform == TargetPlatform.android,
      now: now,
      transactionDate: date,
    );
    if (ent == null) return false;
    final previous = _devicePurchases[p.productID];
    if (previous != null && !(ent.expiresAt ?? now).isAfter(previous.expiresAt ?? now)) return false;
    _devicePurchases[p.productID] = ent;
    return true;
  }

  /// Blaze flow ([FeatureFlags.serverFunctions] on): `verifyPurchase` checks the receipt.
  Future<void> _verifyOnServer(PurchaseDetails p) async {
    try {
      final result = await _server.call('verifyPurchase', {
        'platform': _targetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'productId': p.productID,
        'verificationData': p.verificationData.serverVerificationData,
        'referralCode': _pendingReferralCode,
      });
      final data = Map<String, dynamic>.from(result! as Map);
      _setInOtherFamily(false);
      final ent = Entitlement(
        // Unknown or missing tier = Free, never silently Basic.
        tier: parsePlanTier(data['tier']),
        inTrial: data['inTrial'] as bool? ?? false,
        expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
      );
      _latest = ent;
      _entitlement.add(ent);
    } on ServerCallException catch (e) {
      if (isPurchaseInOtherFamily(e.message)) _setInOtherFamily(true);
      debugPrint('verifyPurchase failed: ${e.code}');
    } catch (e) {
      debugPrint('verifyPurchase failed: $e');
    }
  }

  void dispose() {
    _sub?.cancel();
    _entitlement.close();
    _otherFamily.close();
  }
}

/// `verifyPurchase` error message when the store subscription belongs to another family.
const purchaseInOtherFamilyCode = 'purchase_in_other_family';

bool isPurchaseInOtherFamily(String? message) => message == purchaseInOtherFamilyCode;

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final s = SubscriptionService(server: ref.watch(serverCallsProvider));
  ref.onDispose(s.dispose);
  return s;
});

/// Zero-cost flow: a parent phone writes the plan its store confirmed to the family doc
/// (`plans.<app>` = {plan, planExpiresAt, inTrial: false, source: 'device'}), so the child
/// devices of the family get it ([familyEntitlementProvider]).
///
/// This plan is CLIENT-ASSERTED (owner decision 2026-11-28, accepted weaker anti-fraud): only
/// Firestore rules (parent members only, known tier, bounded expiry) stand between a modified
/// parent app and a free plan. Child safety does not depend on it: a paid tier only adds
/// features, and each child device still enforces its own lock locally. A paired child device
/// never writes the plan. On Blaze, `verifyPurchase` writes it instead.
final familyPlanSharerProvider = Provider<void>((ref) {
  if (ref.watch(featureFlagsProvider).serverFunctions) return;
  ref.listen<Entitlement?>(storeEntitlementProvider.select((v) => v.valueOrNull), (previous, next) {
    if (next == null || next.isFree || identical(previous, next)) return;
    if (ref.read(childrenProvider).isBound) return;
    ref.read(familyRepositoryProvider).shareFamilyPlan(next).catchError((Object e) => debugPrint('plan share failed: $e'));
  }, fireImmediately: true);
});

/// True when this phone's store subscription belongs to another Zad X family: the
/// subscription screen then explains how to link this phone as a parent phone.
final purchaseInOtherFamilyProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(subscriptionServiceProvider);
  yield service.inOtherFamily;
  yield* service.inOtherFamilyStream;
});

/// The latest plan this device's store (or `verifyPurchase` on Blaze) confirmed in this session
/// (`null` until then).
final storeEntitlementProvider = StreamProvider<Entitlement?>((ref) async* {
  final service = ref.watch(subscriptionServiceProvider);
  yield service.latest;
  yield* service.entitlementStream;
});

/// The plan stored on this device's family doc by a parent phone ([familyPlanSharerProvider]; by
/// `verifyPurchase` on Blaze), from snapshots the server sent (never the offline cache). Never
/// emits without Firebase or a family (local mode).
final familyEntitlementProvider = StreamProvider<Entitlement?>(
  (ref) => ref.watch(familyRepositoryProvider).watchEntitlement(),
);

/// Best server-confirmed answer of this session: highest active tier among this device's
/// purchase and the family doc (`null` until one of them answers).
final verifiedEntitlementProvider = Provider<Entitlement?>(
  (ref) => bestVerifiedEntitlement(
    ref.watch(storeEntitlementProvider).valueOrNull,
    ref.watch(familyEntitlementProvider).valueOrNull,
  ),
);

/// Writes every new server confirmation to the [EntitlementCache] (7-day offline grace,
/// clock-rollback safe). Only fires when the confirmation changes, never on the minute tick,
/// so keeping the app open offline cannot stretch the grace.
final entitlementRecorderProvider = Provider<void>((ref) {
  final cache = ref.watch(entitlementCacheProvider);
  ref.listen<Entitlement?>(verifiedEntitlementProvider, (previous, next) {
    if (next != null && !identical(previous, next)) unawaited(cache.recordVerified(next.effectiveTier));
  }, fireImmediately: true);
});

/// Current plan, available synchronously (no loading state, so the lock never flashes open
/// while the plan loads). Re-evaluated every minute so the 7-day trial and the offline grace
/// end on time. Order: verified paid plan (this device or family doc, highest) > cached paid
/// plan (grace) > trial > Free.
/// Free features (lock, prayer times, adhan, Quran, adhkar) never depend on this value.
final planEntitlementProvider = Provider<Entitlement>((ref) {
  ref.watch(clockProvider);
  ref.watch(entitlementRecorderProvider);
  ref.watch(verifiedEntitlementProvider); // runs the recorder before the cache is read
  return resolveEntitlement(
    store: ref.watch(storeEntitlementProvider).valueOrNull,
    family: ref.watch(familyEntitlementProvider).valueOrNull,
    cachedTier: ref.watch(entitlementCacheProvider).effectiveTier(),
    trial: ref.watch(trialClockProvider).status(),
  );
});

/// [planEntitlementProvider] for screens (kept as a stream so tests can override it).
final entitlementProvider = StreamProvider<Entitlement>((ref) => Stream.value(ref.watch(planEntitlementProvider)));
