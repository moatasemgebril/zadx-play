import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_config.dart';
import '../../core/feature_flags.dart';
import '../../core/server_functions.dart';

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
///
/// Hidden today (owner decision 2026-11-28: zero cost, no Cloud Functions): the reward card is
/// behind `FeatureFlags.referralRewards` until a free design exists, and [status] makes no call.
class ReferralService {
  ReferralService({ServerCalls? server}) : _server = server ?? serverCallsFor();

  final ServerCalls _server;

  Future<ReferralStatus> status() async {
    final res = await _server.call('referralStatus');
    final d = Map<String, dynamic>.from(res! as Map);
    return ReferralStatus(code: d['code'] as String, paidFriends: d['paidFriends'] as int? ?? 0);
  }
}

final referralServiceProvider = Provider<ReferralService>((ref) => ReferralService(server: ref.watch(serverCallsProvider)));

/// Placeholder shown when there is no server answer.
const _placeholderStatus = ReferralStatus(code: 'ZADX-0000');

final referralStatusProvider = FutureProvider<ReferralStatus>((ref) async {
  if (!ref.watch(featureFlagsProvider).referralRewards) return _placeholderStatus;
  try {
    return await ref.watch(referralServiceProvider).status();
  } catch (_) {
    // Offline / Firebase not configured yet: show a placeholder code.
    return _placeholderStatus;
  }
});
