import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/app_config.dart';
import '../../core/backend.dart';
import '../../data/models/plan.dart';

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

  Stream<Entitlement> get entitlementStream => _entitlement.stream;
  Map<String, ProductDetails> get products => _products;

  Future<void> init() async {
    if (!await _iap.isAvailable()) return;
    final response = await _iap.queryProductDetails(AppConfig.allProductIds);
    _products = {for (final p in response.productDetails) p.id: p};
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) => debugPrint('IAP error: $e'));
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
          _entitlement.add(Entitlement(
            // Unknown or missing tier = Free, never silently Basic.
            tier: parsePlanTier(data['tier']),
            inTrial: data['inTrial'] as bool? ?? false,
            expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
          ));
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

/// Current plan. Defaults to a trial of Plus so the parent can try everything
/// (a trial always gives Plus features, see `featuresOf`). Free features
/// (lock, prayer times, adhan, Quran) never depend on this provider's value.
final entitlementProvider = StreamProvider<Entitlement>((ref) async* {
  yield const Entitlement(tier: PlanTier.plus, inTrial: true);
  yield* ref.watch(subscriptionServiceProvider).entitlementStream;
});
