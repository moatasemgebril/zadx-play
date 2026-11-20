import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../../features/settings/settings_controller.dart';
import 'family_repository.dart';

enum PairingTarget { phone, windows }

/// Links devices to one family:
/// * parent device → `createPairingCode` (6 digits, 10 minutes)
/// * child phone/tablet → `redeemPairingCode` (adds its uid to `members`)
/// * Windows PC → the Zad X Guard app redeems the code itself and gets a device secret
class PairingService {
  PairingService(this._ref);
  final Ref _ref;

  FirebaseFunctions get _f => zadFunctions();

  Future<String> createCode(PairingTarget target) async {
    final res = await _f.httpsCallable('createPairingCode').call({
      'familyId': _ref.read(familyIdProvider),
      'target': target.name,
    });
    return (res.data as Map)['code'] as String;
  }

  /// Joins the parent's family from this (child) device.
  Future<void> redeem(String code) async {
    final res = await _f.httpsCallable('redeemPairingCode').call({'code': code.trim(), 'target': 'phone'});
    final familyId = (res.data as Map)['familyId'] as String;
    await _ref.read(sharedPrefsProvider).setString('family.id', familyId);
    _ref.read(familyIdProvider.notifier).state = familyId; // repository switches automatically
  }
}

final pairingServiceProvider = Provider<PairingService>(PairingService.new);
