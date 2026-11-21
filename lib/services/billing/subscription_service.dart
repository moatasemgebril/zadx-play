import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/app_config.dart';
import '../../core/backend.dart';
import '../../data/models/plan.dart';
import '../../features/prayer/prayer_providers.dart';
import 'entitlement_cache.dart';
import 'trial_clock.dart';

/// Store subscriptions (App Store / Google Play) + server-side verification.
///
/// Flow: buy() → store sheet → purchaseStream → `verifyPurchase` Cloud Function
/// validates the receipt, stores the entitlement in Firestore and credits the
/// referrer if [referralCode] was used → [entitlementProvider] updates.
class SubscriptionService {
  SubscriptionService({InAppPurchase? iap, FirebaseFunctions? functions})
      : _iap = iap ?? InAppPurchase.instance,
        _functions = functions;

  final InAppPurchase _iap;
  final FirebaseFunctions? _functions;
  final _entitlement = StreamController<Entitlement>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Map<String, ProductDetails> _products = {};
  String? _pendingReferralCode;

  Entitlement? _latest;

  Stream<Entitlement> get entitlementStream => _entitlement.stream;

  /// The last plan `verifyPurchase` confirmed in this session (events sent before anyone
  /// listened are not lost).
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
    if (defaultTargetPlatform == TargetPlatform.android) {
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

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased || p.status == PurchaseStatus.restored) {
        try {
          final result = await (_functions ?? zadFunctions()).httpsCallable('verifyPurchase').call({
            'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
            'productId': p.productID,
            'verificationData': p.verificationData.serverVerificationData,
            'referralCode': _pendingReferralCode,
          });
          final data = Map<String, dynamic>.from(result.data as Map);
          final ent = Entitlement(
            // Unknown or missing tier = Free, never silently Basic.
            tier: parsePlanTier(data['tier']),
            inTrial: data['inTrial'] as bool? ?? false,
            expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
          );
          _latest = ent;
          _entitlement.add(ent);
        } catch (e) {
          debugPrint('verifyPurchase failed: $e');
        }
      }
      if (p.pendingCompletePurchase) await _iap.completePurchase(p);
    }
  }

  void dispose() {
    _sub?.cancel();
    _entitlement.close();
  }
}

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final s = SubscriptionService();
  ref.onDispose(s.dispose);
  return s;
});

/// The latest plan the store + `verifyPurchase` confirmed in this session (`null` until then).
/// Every confirmation is written to the [EntitlementCache] (offline grace).
final storeEntitlementProvider = StreamProvider<Entitlement?>((ref) async* {
  final cache = ref.watch(entitlementCacheProvider);
  final service = ref.watch(subscriptionServiceProvider);
  final latest = service.latest;
  if (latest != null) await cache.recordVerified(latest.effectiveTier);
  yield latest;
  await for (final e in service.entitlementStream) {
    await cache.recordVerified(e.effectiveTier);
    yield e;
  }
});

/// Current plan, available synchronously (no loading state, so the lock never flashes open
/// while the plan loads). Re-evaluated every minute so the 7-day trial and the offline grace
/// end on time. Order: verified paid plan > cached paid plan (grace) > trial > Free.
/// Free features (lock, prayer times, adhan, Quran, adhkar) never depend on this value.
final planEntitlementProvider = Provider<Entitlement>((ref) {
  ref.watch(clockProvider);
  return resolveEntitlement(
    store: ref.watch(storeEntitlementProvider).valueOrNull,
    cachedTier: ref.watch(entitlementCacheProvider).effectiveTier(),
    trial: ref.watch(trialClockProvider).status(),
  );
});

/// [planEntitlementProvider] for screens (kept as a stream so tests can override it).
final entitlementProvider = StreamProvider<Entitlement>((ref) => Stream.value(ref.watch(planEntitlementProvider)));
