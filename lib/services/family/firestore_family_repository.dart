import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/backend.dart';
import '../../data/models/child_profile.dart';
import 'family_repository.dart';
import '../../data/models/plan.dart';

/// Firestore layout (see backend/firestore.rules):
///
/// families/{familyId}
///   members: [uid...]          parents + paired child devices
///   childDevices: {uid: childId} paired child devices (Cloud Functions only)
///   children/{childId}         {nickname, avatar} — no other personal data
///     days/{yyyy-MM-dd}        FamilyDay (`approved`, `earnedMinutes`, `requiredDone` are
///                              written only by the approveTask Cloud Function, R-32)
class FirestoreFamilyRepository implements FamilyRepository {
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
  Future<void> setPrayerPaused({required String childId, required String day, required bool paused}) {
    // Parent devices only (firestore.rules: `prayerPaused` is not a child-device key).
    return _dayDoc(childId, day).set({
      'day': day,
      'prayerPaused': paused,
      if (paused) 'prayerLock': false,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    }, SetOptions(merge: true));
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

  /// Signs in anonymously and creates a family for this device on first launch.
  /// Pairing a second device (parent ⇄ child) adds its uid to `members`
  /// via a short pairing code — see docs/ARCHITECTURE.md.
  static Future<String> ensureFamily(String? existingFamilyId) async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser ?? (await auth.signInAnonymously()).user!;
    if (existingFamilyId != null) return existingFamilyId;
    final doc = await FirebaseFirestore.instance.collection('families').add({
      'members': [user.uid],
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }
}
