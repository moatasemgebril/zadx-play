import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../data/models/child_profile.dart';
import '../../features/settings/settings_controller.dart';
import 'children_controller.dart';
import 'family_repository.dart';

enum PairingTarget { phone, windows }

/// Links devices to one family:
/// * parent device → `createPairingCode` (6 digits, 10 minutes)
/// * child phone/tablet → `redeemPairingCode` (adds its uid to `members` and binds
///   the device to one child via `childDevices`)
/// * Windows PC → the Zad X Guard app redeems the code itself and gets a device secret
class PairingService {
  PairingService(this._ref);
  final Ref _ref;

  FirebaseFunctions get _f => zadFunctions();

  /// Code that links a device to [child]. The profile is synced first so the
  /// server can check that the child exists.
  Future<String> createCode(PairingTarget target, ChildProfile child) async {
    await _ref.read(familyRepositoryProvider).saveChild(child);
    final res = await _f.httpsCallable('createPairingCode').call({
      'familyId': _ref.read(familyIdProvider),
      'target': target.name,
      'childId': child.id,
    });
    return (res.data as Map)['code'] as String;
  }

  /// Joins the parent's family from this (child) device.
  Future<void> redeem(String code) async {
    final res = await _f.httpsCallable('redeemPairingCode').call({'code': code.trim(), 'target': 'phone'});
    final data = Map<String, dynamic>.from(res.data as Map);
    final familyId = data['familyId'] as String;
    final childId = data['childId'] as String? ?? ChildProfile.defaultId;
    if (!ChildProfile.isValidId(childId)) throw StateError('invalid childId');
    final child = ChildProfile(
      id: childId,
      nickname: ChildProfile.cleanNickname(data['nickname'] as String? ?? '') ?? '',
      avatar: ChildProfile.avatarByName(data['avatar'] as String?),
    );
    _ref.read(childrenProvider.notifier).bindTo(child);
    await _ref.read(sharedPrefsProvider).setString('family.id', familyId);
    _ref.read(familyIdProvider.notifier).state = familyId; // repository switches automatically
  }
}

final pairingServiceProvider = Provider<PairingService>(PairingService.new);
