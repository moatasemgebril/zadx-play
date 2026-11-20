import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/backend.dart';

@immutable
class ReferralStatus {
  const ReferralStatus({required this.code, this.paidFriends = 0});

  final String code;

  /// Friends who subscribed AND paid after their trial (counted server-side).
  final int paidFriends;

  int get rewardMonths {
    final capped = paidFriends.clamp(0, AppConfig.referralMaxFriendsPerYear);
    return AppConfig.referralRewards[capped] ?? 0;
  }
}

/// Invite-a-friend rewards: 1 friend → 2 months, 2 → 4, 3 → 6 (max per year).
///
/// All counting and crediting happens in the `referralStatus` / `verifyPurchase`
/// Cloud Functions so it cannot be faked from the client.
class ReferralService {
  ReferralService({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;
  FirebaseFunctions get _f => _functions ?? zadFunctions();

  Future<ReferralStatus> status() async {
    final res = await _f.httpsCallable('referralStatus').call();
    final d = Map<String, dynamic>.from(res.data as Map);
    return ReferralStatus(code: d['code'] as String, paidFriends: d['paidFriends'] as int? ?? 0);
  }
}

final referralServiceProvider = Provider<ReferralService>((_) => ReferralService());

final referralStatusProvider = FutureProvider<ReferralStatus>((ref) async {
  try {
    return await ref.watch(referralServiceProvider).status();
  } catch (_) {
    // Offline / Firebase not configured yet: show a placeholder code.
    return const ReferralStatus(code: 'ZADX-0000');
  }
});
