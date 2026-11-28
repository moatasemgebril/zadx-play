import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/child_profile.dart';
import '../../features/settings/settings_controller.dart';
import '../billing/subscription_service.dart';
import 'children_controller.dart';
import 'family_repository.dart';
import 'firestore_family_repository.dart';
import 'pairing_code.dart';

/// `parent`: "Add a parent phone" (e.g. a new phone after restore). The redeeming phone joins as
/// a parent member, never bound to a child.
enum PairingTarget { phone, windows, parent }

/// Links devices to one family with no server code (zero-cost backend, Firebase Spark plan:
/// docs/ZERO-COST-BACKEND.md). backend/firestore.rules enforces every step:
/// * parent device → writes `pairingCodes/{sha256(code)}` (10 symbols, 10 minutes, see
///   [PairingCode]); only a parent device of the family may, only for an existing child;
/// * child phone/tablet or another parent phone → in ONE transaction reads that doc, adds ITSELF
///   to `members` with exactly the role the code grants (`childDevices` / `parentDevices`) and
///   deletes the code (single use);
/// * Windows PC → Zad X Guard registers itself with a windows code (rules ready; the guard client
///   moves to Firestore in Phase 2). A phone never redeems a windows code.
class PairingService {
  PairingService(this._ref);
  final Ref _ref;

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// The doc id of the last code this phone created: replaced (deleted) by the next one.
  static const lastCodeKey = 'family.lastPairingCodeId';

  static const _timeout = Duration(seconds: 20);

  /// Code that links a device to [child], shown as `XXXXX-XXXXX`. The profile is synced first:
  /// the rules accept a code only for a child that exists.
  Future<String> createCode(PairingTarget target, ChildProfile child) async {
    if (target == PairingTarget.parent) return createParentCode();
    await _ref.read(familyRepositoryProvider).saveChild(child).timeout(_timeout);
    return _issue(target.name, childId: child.id);
  }

  /// Parent device only (the rules refuse child devices): code that links another phone of this
  /// family as a PARENT phone (same 10 minutes, single use).
  Future<String> createParentCode() => _issue('parent');

  Future<String> _issue(String target, {String? childId}) async {
    final familyId = _ref.read(familyIdProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (familyId == null || !isSafeFamilyId(familyId) || uid == null) throw StateError('no synced family');
    final code = PairingCode.generate();
    final docId = PairingCode.docId(code);
    await _db.doc('pairingCodes/$docId').set({
      'familyId': familyId,
      'target': target,
      if (childId != null) 'childId': childId,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
    // Only one live code per phone: the previous one is withdrawn (best effort).
    final prefs = _ref.read(sharedPrefsProvider);
    final previous = prefs.getString(lastCodeKey);
    await prefs.setString(lastCodeKey, docId);
    if (previous != null && previous != docId && PairingCode.isDocId(previous)) {
      unawaited(_db.doc('pairingCodes/$previous').delete().catchError((Object e) {
        debugPrint('old pairing code not withdrawn: $e'); // already used or expired: fine
      }));
    }
    return PairingCode.display(code);
  }

  /// Joins the parent's family from this device: as a child device for a phone code, or as a
  /// parent phone for a parent code (the CODE decides, never this device). Throws
  /// [PairingRejected] for a wrong, used or expired code.
  Future<void> redeem(String input) async {
    final code = PairingCode.normalize(input);
    if (code == null) throw const PairingRejected('invalid_code');
    final uid = FirebaseAuth.instance.currentUser?.uid ?? await FirestoreFamilyRepository.signIn();
    final codeId = PairingCode.docId(code);
    final codeRef = _db.doc('pairingCodes/$codeId');

    // A missing, used or expired code is the same permission-denied (no oracle for guessing).
    final info = await _readCode(codeRef);
    if (info == null || info.target == 'windows') throw const PairingRejected('invalid_code');
    final oldFamilyId = _ref.read(familyIdProvider);
    final leaving = oldFamilyId != null && oldFamilyId != info.familyId && isSafeFamilyId(oldFamilyId) ? oldFamilyId : null;
    if (info.isParent && leaving != null) {
      // Same rule as the old server: a phone whose own family already has children is not merged
      // into another family by a parent code (its data would be stranded).
      final kids = await _db
          .collection('families/$leaving/children')
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(_timeout);
      if (kids.docs.isNotEmpty) throw const PairingRejected('parent_link_family_in_use');
    }

    final joined = await _db.runTransaction<PairingCodeInfo?>((tx) async {
      final live = await _readCodeIn(tx, codeRef);
      if (live == null || live.familyId != info.familyId || live.target != info.target) return null;
      tx.update(_db.doc('families/${live.familyId}'), {
        'members': FieldValue.arrayUnion([uid]),
        if (live.isParent) 'parentDevices.$uid': FieldValue.serverTimestamp() else 'childDevices.$uid': live.childId,
        'memberOp': {'op': 'join', 'uid': uid, 'code': codeId, 'at': FieldValue.serverTimestamp()},
      });
      tx.delete(codeRef);
      return live;
    }).timeout(_timeout);
    if (joined == null) throw const PairingRejected('invalid_code');

    final prefs = _ref.read(sharedPrefsProvider);
    if (joined.isParent) {
      await prefs.setString('family.id', joined.familyId);
      _ref.read(familyIdProvider.notifier).state = joined.familyId; // repository + family plan switch
      // Re-verify this phone's store subscription: it now belongs to this family.
      unawaited(_ref.read(subscriptionServiceProvider).restore().catchError((Object _) {}));
      // The untouched fresh family this phone leaves is deleted (rules: sole member, fresh fields).
      if (leaving != null) {
        unawaited(_db.doc('families/$leaving').delete().catchError((Object e) {
          debugPrint('old family not deleted: $e');
        }));
      }
      return;
    }
    final childId = joined.childId ?? ChildProfile.defaultId;
    if (!ChildProfile.isValidId(childId)) throw StateError('invalid childId');
    // Now a member bound to this child: the profile (nickname + avatar only) is readable.
    Map<String, dynamic>? profile;
    try {
      profile = (await _db.doc('families/${joined.familyId}/children/$childId').get().timeout(_timeout)).data();
    } catch (e) {
      debugPrint('child profile not loaded yet: $e'); // it syncs later; defaults until then
    }
    final child = ChildProfile(
      id: childId,
      nickname: ChildProfile.cleanNickname(profile?['nickname'] as String? ?? '') ?? '',
      avatar: ChildProfile.avatarByName(profile?['avatar'] as String?),
    );
    _ref.read(childrenProvider.notifier).bindTo(child);
    await prefs.setString('family.id', joined.familyId);
    _ref.read(familyIdProvider.notifier).state = joined.familyId; // repository switches automatically
  }

  /// The code doc from the server, or null when it is missing, used, expired or malformed.
  Future<PairingCodeInfo?> _readCode(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      final snap = await ref.get(const GetOptions(source: Source.server)).timeout(_timeout);
      return PairingCodeInfo.tryParse(snap.data());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }

  /// Same, inside the join transaction (the commit then depends on this read).
  static Future<PairingCodeInfo?> _readCodeIn(Transaction tx, DocumentReference<Map<String, dynamic>> ref) async {
    try {
      return PairingCodeInfo.tryParse((await tx.get(ref)).data());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') return null;
      rethrow;
    }
  }
}

final pairingServiceProvider = Provider<PairingService>(PairingService.new);

/// Firestore ids as the server issues them (letters, digits, '-', '_').
bool isSafeFamilyId(String id) => RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);
