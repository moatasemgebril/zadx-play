import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/app_config.dart';
import '../../core/backend.dart';
import '../../data/models/plan.dart';
import '../../features/prayer/prayer_providers.dart';
import '../family/family_repository.dart';
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
          _setInOtherFamily(false);
          final ent = Entitlement(
            // Unknown or missing tier = Free, never silently Basic.
            tier: parsePlanTier(data['tier']),
            inTrial: data['inTrial'] as bool? ?? false,
            expiresAt: DateTime.tryParse(data['expiresAt'] as String? ?? ''),
          );
          _latest = ent;
          _entitlement.add(ent);
        } on FirebaseFunctionsException catch (e) {
          if (isPurchaseInOtherFamily(e.message)) _setInOtherFamily(true);
          debugPrint('verifyPurchase failed: ${e.code}');
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
    _otherFamily.close();
  }
}

/// `verifyPurchase` error message when the store subscription belongs to another family.
const purchaseInOtherFamilyCode = 'purchase_in_other_family';

bool isPurchaseInOtherFamily(String? message) => message == purchaseInOtherFamilyCode;

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final s = SubscriptionService();
  ref.onDispose(s.dispose);
  return s;
});

/// True when this phone's store subscription belongs to another Zad X family: the
/// subscription screen then explains how to link this phone as a parent phone.
final purchaseInOtherFamilyProvider = StreamProvider<bool>((ref) async* {
  final service = ref.watch(subscriptionServiceProvider);
  yield service.inOtherFamily;
  yield* service.inOtherFamilyStream;
});

/// The latest plan the store + `verifyPurchase` confirmed in this session (`null` until then).
final storeEntitlementProvider = StreamProvider<Entitlement?>((ref) async* {
  final service = ref.watch(subscriptionServiceProvider);
  yield service.latest;
  yield* service.entitlementStream;
});

/// The plan stored on this device's family doc by `verifyPurchase` (bought on any family phone),
/// server-confirmed snapshots only. Never emits without Firebase or a family (local mode).
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
