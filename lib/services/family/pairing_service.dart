import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../data/models/child_profile.dart';
import '../../features/settings/settings_controller.dart';
import '../billing/subscription_service.dart';
import 'children_controller.dart';
import 'family_repository.dart';

/// `parent`: "Add a parent phone" (e.g. a new phone after restore). The redeeming phone joins as
/// a parent member, never bound to a child.
enum PairingTarget { phone, windows, parent }

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
    if (target == PairingTarget.parent) return createParentCode();
    await _ref.read(familyRepositoryProvider).saveChild(child);
    final res = await _f.httpsCallable('createPairingCode').call({
      'familyId': _ref.read(familyIdProvider),
      'target': target.name,
      'childId': child.id,
    });
    return (res.data as Map)['code'] as String;
  }

  /// Parent device only (the server refuses child devices): code that links another phone of
  /// this family as a PARENT phone (same 6 digits, 10 minutes, single use).
  Future<String> createParentCode() async {
    final res = await _f.httpsCallable('createPairingCode').call({
      'familyId': _ref.read(familyIdProvider),
      'target': 'parent',
    });
    return (res.data as Map)['code'] as String;
  }

  /// Joins the parent's family from this device: as a child device for a child code, or as a
  /// parent phone for a parent code (the server decides from the code, never from the client).
  Future<void> redeem(String code) async {
    final res = await _f.httpsCallable('redeemPairingCode').call({'code': code.trim(), 'target': 'phone'});
    final data = Map<String, dynamic>.from(res.data as Map);
    final familyId = data['familyId'] as String;
    if (!isSafeFamilyId(familyId)) throw StateError('invalid familyId');
    if (data['role'] == 'parent') {
      await _ref.read(sharedPrefsProvider).setString('family.id', familyId);
      _ref.read(familyIdProvider.notifier).state = familyId; // repository + family plan switch
      // Re-verify this phone's store subscription: it now belongs to this family.
      unawaited(_ref.read(subscriptionServiceProvider).restore().catchError((Object _) {}));
      return;
    }
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

/// Firestore ids as the server issues them (letters, digits, '-', '_').
bool isSafeFamilyId(String id) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);
