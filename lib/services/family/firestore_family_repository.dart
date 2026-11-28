import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/foundation.dart';

import '../../core/backend.dart';
import '../../core/server_functions.dart';
import '../../data/models/child_profile.dart';
import 'child_pause.dart';
import 'device_removal.dart';
import 'family_events.dart';
import 'family_repository.dart';
import 'firestore_family_events.dart';
import '../../data/models/plan.dart';

/// Firestore layout (see backend/firestore.rules):
///
/// families/{familyId}
///   members: [uid...]          parents + paired child devices
///   childDevices: {uid: childId} paired child devices (Cloud Functions only)
///   parentDevices: {uid: linkedAt} linked parent phones (Cloud Functions only); a member is
///                              removed only by the removeLinkedDevice Cloud Function (P1-3)
///   children/{childId}         {nickname, avatar} — no other personal data
///     days/{yyyy-MM-dd}        FamilyDay (`approved`, `earnedMinutes`, `requiredDone` are
///                              written only by the approveTask Cloud Function, R-32)
class FirestoreFamilyRepository implements FamilyRepository, MembershipSource {
  FirestoreFamilyRepository({
    required this.familyId,
    FirebaseFirestore? db,
    FirebaseFunctions? functions,
  })  : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? zadFunctions();

  final String familyId;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  /// Used minutes last known to be on the server, per "childId/day". The app sends only the
  /// minutes added since then (FieldValue.increment), so it never lowers the server value (the
  /// rules refuse that for child devices) and never overwrites minutes the Windows guard added.
  final Map<String, int> _usedOnServer = {};

  DocumentReference<Map<String, dynamic>> _dayDoc(String childId, String day) =>
      _db.doc('families/$familyId/children/$childId/days/$day');

  @override
  Stream<FamilyDay> watchDay(String childId, String day) {
    final key = '$childId/$day';
    return _dayDoc(childId, day)
        .snapshots(includeMetadataChanges: false)
        .where((s) => !s.metadata.hasPendingWrites)
        .map((s) {
          _usedOnServer[key] = (s.data()?['usedMinutes'] as num?)?.toInt() ?? 0;
          return s;
        })
        .where((s) => s.exists)
        .map((s) {
          final data = Map<String, dynamic>.from(s.data()!);
          final lockAt = data.remove('prayerLockAt');
          if (lockAt is Timestamp) data['prayerLockAtMs'] = lockAt.millisecondsSinceEpoch;
          // Legacy device-clock value from older builds: never trusted, only the server time counts.
          data.remove('prayerLockSinceMs');
          data.remove('updatedAt');
          // Server-only credits: an absent map means "nothing approved yet" (never null here).
          data['approved'] = FamilyDay.parseCredits(data['approved']) ?? <String, int>{};
          return FamilyDay.fromJson(data);
        });
  }

  @override
  Stream<Entitlement> watchEntitlement() {
    return _db
        .doc('families/$familyId')
        .snapshots(includeMetadataChanges: true)
        // Server-confirmed only: a cached snapshot must not refresh the offline grace.
        .where((s) => s.exists && !s.metadata.isFromCache)
        .map((s) {
      final data = Map<String, dynamic>.from(s.data()!);
      final expiry = data['planExpiresAt'];
      if (expiry is Timestamp) data['planExpiresAt'] = expiry.toDate();
      final plans = data['plans'];
      if (plans is Map) {
        data['plans'] = {
          for (final e in plans.entries)
            e.key: e.value is Map
                ? {
                    for (final f in (e.value as Map).entries) f.key: f.value is Timestamp ? (f.value as Timestamp).toDate() : f.value,
                  }
                : e.value,
        };
      }
      return parseFamilyEntitlement(data);
    });
  }

  @override
  bool get serverApprovals => true;

  @override
  Future<void> saveDay(String childId, FamilyDay day, {bool lockChanged = false}) async {
    final key = '$childId/${day.day}';
    final data = <String, Object?>{
      'day': day.day,
      'progress': day.progress,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    };
    final onServer = _usedOnServer[key];
    if (onServer != null && day.usedMinutes > onServer) {
      data['usedMinutes'] = FieldValue.increment(day.usedMinutes - onServer);
      _usedOnServer[key] = day.usedMinutes;
    }
    if (lockChanged) {
      data['prayerLock'] = day.prayerLock;
      if (day.prayerLock) {
        // Server time of the lock: the rules end a child's lock only after the window from here.
        // The device-clock start (`prayerLockSinceMs`) stays on this device: the rules refuse it,
        // because a child could back-date it to shorten the lock.
        data['prayerLockAt'] = FieldValue.serverTimestamp();
      }
    }
    await _dayDoc(childId, day.day).set(data, SetOptions(merge: true));
  }

  @override
  Future<void> approveTask({
    required String childId,
    required String day,
    required String taskId,
    required int minutes,
    required List<String> requiredTaskIds,
    required bool isPrayer,
  }) =>
      _callApproval('approveTask', {
        'familyId': familyId,
        'childId': childId,
        'day': day,
        'taskId': taskId,
        'minutes': minutes,
        'requiredTaskIds': requiredTaskIds,
        'isPrayer': isPrayer,
      });

  @override
  Future<void> rejectTask({required String childId, required String day, required String taskId}) =>
      _callApproval('rejectTask', {'familyId': familyId, 'childId': childId, 'day': day, 'taskId': taskId});

  /// Errors that will not go away by retrying become [ApprovalRejected]; the rest (offline,
  /// timeouts, server busy) are rethrown so the caller queues the approval.
  static const _transient = {'unavailable', 'deadline-exceeded', 'internal', 'unknown', 'aborted', 'resource-exhausted', 'cancelled'};

  Future<void> _callApproval(String name, Map<String, Object?> payload) async {
    try {
      await _functions.httpsCallable(name).call(payload);
    } on FirebaseFunctionsException catch (e) {
      if (_transient.contains(e.code)) rethrow;
      throw ApprovalRejected(e.code);
    }
  }

  @override
  Future<void> saveChild(ChildProfile child) => _db.doc('families/$familyId/children/${child.id}').set({
        'nickname': child.nickname,
        'avatar': child.avatar.name,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteChild(String childId) async {
    final days = _db.collection('families/$familyId/children/$childId/days');
    while (true) {
      final page = await days.limit(200).get();
      if (page.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
    await _db.doc('families/$familyId/children/$childId').delete();
  }

  @override
  Future<void> saveSettings(Map<String, Object?> settings) =>
      _db.doc('families/$familyId').set({'settings': settings}, SetOptions(merge: true));

  // ---- Parent alerts, presence, shared plan (zero-cost backend, firestore_family_events.dart) ----

  /// Cloud Functions only on Blaze (`FeatureFlags.serverFunctions`); off by default.
  final ServerCalls _server = serverCallsFor();
  late final FirestoreFamilyEvents _alerts = FirestoreFamilyEvents(familyId: familyId, db: _db);

  @override
  Future<void> notifyParent(String childId, String type, {Map<String, Object?> data = const {}}) async {
    if (!_server.enabled) return _alerts.addEvent(type, childId, detail: eventDetailFrom(data));
    try {
      await _server.call('notifyParent', {'familyId': familyId, 'childId': childId, 'type': type, 'data': data});
    } catch (e) {
      debugPrint('notifyParent failed: $e');
    }
  }

  @override
  Future<void> reportProtection(String childId, {required String platform, required List<String> reasons}) async {
    if (!_server.enabled) return _alerts.reportProtection(childId, platform: platform, reasons: reasons);
    await _server.call('reportProtection', {
      'familyId': familyId,
      'childId': childId,
      'status': {'platform': platform, 'reasons': reasons},
    });
  }

  @override
  Future<void> touchPresence(String childId, {required String platform}) => _alerts.touchPresence(childId, platform: platform);

  @override
  Stream<List<FamilyEvent>> watchEvents() => _alerts.watchEvents();

  @override
  Stream<Map<String, ChildPresence>> watchPresence() => _alerts.watchPresence();

  @override
  Future<void> pruneEvents() => _alerts.pruneEvents();

  @override
  Future<void> shareFamilyPlan(Entitlement plan) async {
    // On Blaze `verifyPurchase` writes the plan (server-verified); never overwrite it from here.
    if (_server.enabled) return;
    await _alerts.shareFamilyPlan(plan);
  }

  @override
  Stream<List<LinkedDevice>> watchLinkedDevices() => _db
      .doc('families/$familyId')
      .snapshots()
      .where((s) => s.exists)
      .map((s) => parseLinkedDevices(s.data()!, FirebaseAuth.instance.currentUser?.uid));

  /// Reasons the `removeLinkedDevice` Function sends as the error message.
  static const _removalReasons = {'last_parent', 'parent_required', 'device_not_found', 'not_member'};

  @override
  Future<void> removeLinkedDevice(String deviceUid) async {
    try {
      await _functions.httpsCallable('removeLinkedDevice').call({'familyId': familyId, 'deviceUid': deviceUid});
    } on FirebaseFunctionsException catch (e) {
      throw DeviceRemovalRejected(_removalReasons.contains(e.message) ? e.message! : e.code);
    } catch (_) {
      throw const DeviceRemovalRejected('unknown');
    }
  }

  /// Removed-device hint (P1-3a): a refused family-doc listener. Data and other errors are dropped.
  @override
  Stream<void> accessDenied() => _db.doc('families/$familyId').snapshots().transform(
        StreamTransformer<DocumentSnapshot<Map<String, dynamic>>, void>.fromHandlers(
          handleData: (_, __) {},
          handleError: (error, _, sink) {
            if (isPermissionDenied(error)) sink.add(null);
          },
        ),
      );

  /// The explicit server answer (`checkDeviceMembership`, admin SDK) about this device's own uid.
  /// A revoked session was signed out by Firebase Auth: a new anonymous session asks instead (it
  /// is not a member either). Offline, timeouts and any error are [MembershipProbe.unknown].
  @override
  Future<MembershipProbe> probe() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) await auth.signInAnonymously().timeout(const Duration(seconds: 10));
      final res = await _functions
          .httpsCallable('checkDeviceMembership')
          .call({'familyId': familyId}).timeout(const Duration(seconds: 15));
      return membershipFromServer(res.data);
    } catch (_) {
      return MembershipProbe.unknown;
    }
  }

  @override
  Stream<FamilyPlanStatus> watchFamilyStatus() => _db.doc('families/$familyId').snapshots().where((s) => s.exists).map((s) {
        final d = Map<String, dynamic>.from(s.data()!);
        final created = d['createdAt'];
        if (created is Timestamp) d['createdAt'] = created.millisecondsSinceEpoch;
        // Per-app plans (plans.<app>): this build's own plan, same as parseFamilyEntitlement.
        final plan = familyPlanFieldsFor(d, currentStoreApp);
        d['plan'] = plan['plan'];
        d['planExpiresAt'] = plan['planExpiresAt'];
        return FamilyPlanStatus.fromFamilyDoc(d);
      });

  @override
  Future<bool> setFreeChild(String childId) async {
    await _functions.httpsCallable('setFreeChild').call({'familyId': familyId, 'childId': childId});
    return true;
  }

  /// Signs in anonymously (cached after the first launch) and returns the uid.
  static Future<String> signIn() async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
    return user.uid;
  }

  /// A new family id, generated on the device (no network): FamilyBootstrap saves it locally
  /// before the family doc is written, so a timed-out write can never leave an orphan family.
  static String newFamilyId() => FirebaseFirestore.instance.collection('families').doc().id;

  /// Creates families/[familyId] with this device as its only member. Idempotent, so start-up can
  /// retry it with the same id: on a new doc this is a create (`members == [uid]` in
  /// firestore.rules); when an earlier, timed-out attempt already landed, `arrayUnion` of a uid
  /// that is already there changes nothing. Pairing a second device (parent ⇄ child) adds its uid
  /// to `members` via a short pairing code — see docs/ARCHITECTURE.md.
  ///
  /// Free plan = one child: the server's 7-day family trial counts from `createdAt` (server time;
  /// firestore.rules only accepts `request.time`). `createdAt` is server-only after the create, so
  /// a retry whose earlier attempt already landed is refused with permission-denied and falls
  /// back to the plain `members` write.
  static Future<void> createFamily(String familyId, String uid) async {
    final doc = FirebaseFirestore.instance.doc('families/$familyId');
    try {
      await doc.set({
        'members': FieldValue.arrayUnion([uid]),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      await doc.set({
        'members': FieldValue.arrayUnion([uid]),
      }, SetOptions(merge: true));
    }
  }
}
