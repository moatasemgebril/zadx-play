import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/backend.dart';
import '../../data/models/child_profile.dart';
import 'child_pause.dart';
import 'device_removal.dart';
import 'family_core_logic.dart';
import 'family_repository.dart';
import '../../data/models/plan.dart';

/// Firestore layout (see backend/firestore.rules and docs/ZERO-COST-BACKEND.md). Zero cost:
/// Firebase Spark plan, no Cloud Functions; every family-core invariant is enforced by the rules.
///
/// families/{familyId}
///   members: [uid...]          parents + paired child devices
///   childDevices: {uid: childId} paired child devices (written only by a rules-checked pairing join)
///   parentDevices: {uid: linkedAt} linked parent phones (same)
///   memberOp: {...}            the last membership change (join / remove), checked by the rules
///   freeChildId                the child that stays active on Free (parent devices only)
///   removedDevices/{uid}       {removedAt}: removal marker, readable only by that uid (P1-3a)
///   audit/{autoId}             device-removal audit, append-only
///   children/{childId}         {nickname, avatar} — no other personal data
///     days/{yyyy-MM-dd}        FamilyDay (`approved`, `earnedMinutes`, `requiredDone` change only
///                              in a parent-device approval write, R-32)
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
          data.remove('approval'); // rules bookkeeping of the last approval (holds a Timestamp)
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
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const ApprovalRejected('unauthenticated');
    final error = approvalRequestError(
      day: day,
      taskId: taskId,
      minutes: minutes,
      requiredTaskIds: requiredTaskIds,
      now: DateTime.now(),
    );
    if (error != null || !ChildProfile.isValidId(childId)) throw ApprovalRejected(error ?? 'invalid-argument');
    final ref = _dayDoc(childId, day);
    // One transaction on the day doc: read the credits, add this one (once, capped), write. The
    // rules (parentApprovalOk) allow it only for a parent device and check every number again.
    await _guardApproval(() => _db.runTransaction<void>((tx) async {
          final snap = await tx.get(ref);
          final data = snap.data() ?? const <String, dynamic>{};
          final out = applyApproval(
            approvedBefore: data['approved'],
            earnedBefore: data['earnedMinutes'],
            taskId: taskId,
            minutes: minutes,
            requiredTaskIds: requiredTaskIds,
          );
          final update = <String, dynamic>{
            'day': day,
            'approval': {'taskId': taskId, 'by': uid, 'at': FieldValue.serverTimestamp()},
            'approved': {taskId: out.credit},
            'earnedMinutes': out.earnedMinutes,
            'requiredDone': out.requiredDone,
            'progress': {
              taskId: {'status': 'done', 'count': progressCount(data['progress'], taskId)},
            },
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': uid,
          };
          // Approving "I prayed" ends the prayer lock (before the window, only a parent can end it).
          if (isPrayer) {
            update['prayerLock'] = false;
            if (data.containsKey('prayerLockSinceMs')) update['prayerLockSinceMs'] = FieldValue.delete();
            if (data.containsKey('prayerLockAt')) update['prayerLockAt'] = FieldValue.delete();
          }
          tx.set(ref, update, SetOptions(merge: true));
        }));
  }

  @override
  Future<void> rejectTask({required String childId, required String day, required String taskId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const ApprovalRejected('unauthenticated');
    if (!isApprovalDay(day, DateTime.now()) || !isTaskId(taskId) || !ChildProfile.isValidId(childId)) {
      throw const ApprovalRejected('invalid-argument');
    }
    // Back to "todo" (credits already given stay). A plain parent write: no credit field changes.
    await _guardApproval(() => _dayDoc(childId, day).set({
          'day': day,
          'progress': {
            taskId: {'status': 'todo', 'count': 0},
          },
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': uid,
        }, SetOptions(merge: true)));
  }

  /// Errors that will not go away by retrying become [ApprovalRejected] (e.g. permission-denied
  /// on a child device); the rest (offline, timeouts, contention) are rethrown so the caller
  /// queues the approval.
  static const _transient = {'unavailable', 'deadline-exceeded', 'internal', 'unknown', 'aborted', 'resource-exhausted', 'cancelled'};

  /// A write that waits for the server (a plain `set` never fails offline: it would wait for the
  /// connection forever) has 20 seconds; a timeout is transient.
  static const _writeTimeout = Duration(seconds: 20);

  Future<void> _guardApproval(Future<void> Function() write) async {
    try {
      await write().timeout(_writeTimeout);
    } on FirebaseException catch (e) {
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

  @override
  Future<void> notifyParent(String childId, String type, {Map<String, Object?> data = const {}}) async {
    await _functions.httpsCallable('notifyParent').call({
      'familyId': familyId,
      'childId': childId,
      'type': type,
      'data': data,
    });
  }

  @override
  Future<void> reportProtection(String childId, {required String platform, required List<String> reasons}) async {
    await _functions.httpsCallable('reportProtection').call({
      'familyId': familyId,
      'childId': childId,
      'status': {'platform': platform, 'reasons': reasons},
    });
  }

  @override
  Stream<List<LinkedDevice>> watchLinkedDevices() => _db
      .doc('families/$familyId')
      .snapshots()
      .where((s) => s.exists)
      .map((s) => parseLinkedDevices(s.data()!, FirebaseAuth.instance.currentUser?.uid));

  /// Parent device: removes [deviceUid] in ONE transaction that the rules check together
  /// (removeOk / auditEntryOk / removedDevices in backend/firestore.rules): the member leaves
  /// `members`, `childDevices` and `parentDevices`; its removal marker (the explicit answer its
  /// own app reads, P1-3a) and an append-only audit entry (uids + role + time, no child data) are
  /// written in the same commit. Never the last parent device. Refusals are
  /// [DeviceRemovalRejected] with the reason the UI knows (`last_parent`, `parent_required`, ...).
  @override
  Future<void> removeLinkedDevice(String deviceUid) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw const DeviceRemovalRejected('not_member');
    if (!isSafeId(deviceUid)) throw const DeviceRemovalRejected('device_not_found');
    final familyRef = _db.doc('families/$familyId');
    final auditRef = familyRef.collection('audit').doc();
    final markerRef = familyRef.collection('removedDevices').doc(deviceUid);
    String? refused;
    try {
      refused = await _db.runTransaction<String?>((tx) async {
        final snap = await tx.get(familyRef);
        final decision = removeDeviceDecision(snap.data() ?? const <String, dynamic>{}, uid, deviceUid);
        final role = decision.role;
        if (role == null) return decision.reason ?? 'unknown';
        tx.update(familyRef, {
          'members': FieldValue.arrayRemove([deviceUid]),
          'childDevices.$deviceUid': FieldValue.delete(),
          'parentDevices.$deviceUid': FieldValue.delete(),
          'memberOp': {'op': 'remove', 'uid': deviceUid, 'by': uid, 'at': FieldValue.serverTimestamp(), 'audit': auditRef.id},
        });
        tx.set(markerRef, {'removedAt': FieldValue.serverTimestamp()});
        tx.set(auditRef, {
          'action': 'device_removed',
          'byUid': uid,
          'targetUid': deviceUid,
          'targetRole': role.name,
          'at': FieldValue.serverTimestamp(),
          // Optional Firestore TTL policy on `expiresAt` (collection group `audit`): about a year.
          'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 365))),
        });
        return null;
      }).timeout(_writeTimeout);
    } on FirebaseException catch (e) {
      throw DeviceRemovalRejected(e.code);
    } catch (_) {
      throw const DeviceRemovalRejected('unknown');
    }
    if (refused != null) throw DeviceRemovalRejected(refused);
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

  /// The explicit answer about this device's own uid, from two SERVER reads (never the cache):
  /// the family doc (readable = member), and when that is refused, this device's removal marker
  /// `removedDevices/{uid}` (exists = removed; see [membershipFromFirestore]). No session, offline,
  /// timeouts and any other error are [MembershipProbe.unknown].
  @override
  Future<MembershipProbe> probe() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return MembershipProbe.unknown;
      const server = GetOptions(source: Source.server);
      const timeout = Duration(seconds: 15);
      try {
        final family = await _db.doc('families/$familyId').get(server).timeout(timeout);
        final members = family.data()?['members'];
        return membershipFromFirestore(uid: uid, familyMembers: members is List ? List<Object?>.from(members) : const []);
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') return MembershipProbe.unknown;
      }
      final marker = await _db.doc('families/$familyId/removedDevices/$uid').get(server).timeout(timeout);
      return membershipFromFirestore(uid: uid, removedMarker: marker.exists);
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

  /// Parent device: the child that stays active on Free. A plain family-doc write that the rules
  /// (freeChildOk) allow only for a parent device and only for `child-1` or an existing child.
  @override
  Future<bool> setFreeChild(String childId) async {
    if (!ChildProfile.isValidId(childId)) return false;
    await _db.doc('families/$familyId').update({'freeChildId': childId}).timeout(_writeTimeout);
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
