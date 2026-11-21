import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/backend.dart';
import '../../data/models/child_profile.dart';
import 'family_repository.dart';

/// Firestore layout (see backend/firestore.rules):
///
/// families/{familyId}
///   members: [uid...]          parents + paired child devices
///   childDevices: {uid: childId} paired child devices (Cloud Functions only)
///   children/{childId}         {nickname, avatar} — no other personal data
///     days/{yyyy-MM-dd}        FamilyDay
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

  DocumentReference<Map<String, dynamic>> _dayDoc(String childId, String day) =>
      _db.doc('families/$familyId/children/$childId/days/$day');

  @override
  Stream<FamilyDay> watchDay(String childId, String day) {
    return _dayDoc(childId, day)
        .snapshots(includeMetadataChanges: false)
        .where((s) => s.exists && !s.metadata.hasPendingWrites)
        .map((s) => FamilyDay.fromJson(s.data()!));
  }

  @override
  Future<void> saveDay(String childId, FamilyDay day) async {
    await _dayDoc(childId, day.day).set({
      ...day.toJson(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    }, SetOptions(merge: true));
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
