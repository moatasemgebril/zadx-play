import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../data/models/plan.dart';
import 'family_events.dart';
import 'family_repository.dart' show currentStoreApp;

/// Zero-cost backend (Spark, no Cloud Functions) for parent alerts, presence and the shared plan.
/// Used by [FirestoreFamilyRepository] while `FeatureFlags.serverFunctions` is off.
///
/// Firestore layout (rules: docs/decisions/SPARK-APP-NO-FUNCTIONS.md):
///
/// families/{familyId}
///   plans.<app>              {plan, planExpiresAt (ISO-8601), inTrial: false, source: 'device',
///                            updatedBy, updatedAt}: written by a PARENT phone (client-asserted)
///   events/{eventId}         {type, childId, at, by, detail?, reasons?}: created by a family
///                            device, read + deleted by parent phones
///   presence/{childId}       {childId, lastSeen, platform, by, protection?}: written by the child
///                            device bound to childId, read by parent phones
///
/// Every write is best-effort: errors are logged, never shown to the child.
class FirestoreFamilyEvents {
  FirestoreFamilyEvents({required this.familyId, required FirebaseFirestore db, String? Function()? uid})
      : _db = db,
        _uid = uid ?? (() => FirebaseAuth.instance.currentUser?.uid);

  final String familyId;
  final FirebaseFirestore _db;
  final String? Function() _uid;

  /// Protection reasons last stored on the presence doc, per child (read once per session).
  final Map<String, List<String>> _reported = {};

  CollectionReference<Map<String, dynamic>> get _events => _db.collection('families/$familyId/events');
  DocumentReference<Map<String, dynamic>> _presence(String childId) => _db.doc('families/$familyId/presence/$childId');

  Future<void> addEvent(String type, String childId, {String? detail, List<String> reasons = const []}) async {
    try {
      await _events.add({
        ...eventFields(type, childId, detail: detail, reasons: reasons),
        'at': FieldValue.serverTimestamp(),
        'by': _uid(),
      });
    } catch (e) {
      debugPrint('family event failed: $e');
    }
  }

  Future<void> touchPresence(String childId, {required String platform}) async {
    try {
      await _presence(childId).set({
        'childId': childId,
        'lastSeen': FieldValue.serverTimestamp(),
        'platform': platform,
        'by': _uid(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('presence failed: $e');
    }
  }

  /// Stores the current protection state on the presence doc and writes one `protection` event
  /// for reasons that are new since the last report. Unchanged state: no write at all.
  Future<void> reportProtection(String childId, {required String platform, required List<String> reasons}) async {
    try {
      final current = cleanTamperReasons(reasons);
      final previous = _reported[childId] ?? await _storedReasons(childId);
      if (listEquals(previous, current)) {
        _reported[childId] = current;
        return;
      }
      await _presence(childId).set({
        'childId': childId,
        'lastSeen': FieldValue.serverTimestamp(),
        'platform': platform,
        'by': _uid(),
        'protection': current,
      }, SetOptions(merge: true));
      _reported[childId] = current;
      final fresh = newTamperReasons(previous, current);
      if (fresh.isNotEmpty) await addEvent(FamilyEventType.protection, childId, reasons: fresh);
    } catch (e) {
      debugPrint('protection report failed: $e');
    }
  }

  /// The reasons on the presence doc (the local cache when offline; none if never written).
  Future<List<String>> _storedReasons(String childId) async {
    final snap = await _presence(childId).get();
    final raw = snap.data()?['protection'];
    return raw is List ? cleanTamperReasons(raw.whereType<String>()) : const [];
  }

  Stream<List<FamilyEvent>> watchEvents() {
    final from = Timestamp.fromDate(DateTime.now().toUtc().subtract(eventRetention));
    return _events.where('at', isGreaterThan: from).orderBy('at', descending: true).limit(50).snapshots().map(
          (q) => [
            for (final d in q.docs)
              if (FamilyEvent.tryParse(d.id, _plain(d.data())) case final FamilyEvent e) e,
          ],
        );
  }

  Stream<Map<String, ChildPresence>> watchPresence() => _db.collection('families/$familyId/presence').snapshots().map(
        (q) => {
          for (final d in q.docs)
            if (ChildPresence.tryParse(d.id, _plain(d.data())) case final ChildPresence p) d.id: p,
        },
      );

  Future<void> pruneEvents() async {
    try {
      final before = Timestamp.fromDate(DateTime.now().toUtc().subtract(eventRetention));
      final old = await _events.where('at', isLessThan: before).limit(100).get();
      if (old.docs.isEmpty) return;
      final batch = _db.batch();
      for (final d in old.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint('event prune failed: $e');
    }
  }

  /// Parent phone: the plan this phone's store confirmed, for the whole family (client-asserted).
  Future<void> shareFamilyPlan(Entitlement plan) async {
    final tier = plan.effectiveTier;
    final expiresAt = plan.expiresAt;
    if (tier == null || expiresAt == null) return;
    await _db.doc('families/$familyId').set({
      'plans': {
        currentStoreApp: {
          'plan': tier.name,
          'planExpiresAt': expiresAt.toUtc().toIso8601String(),
          'inTrial': false,
          'source': 'device',
          'updatedBy': _uid(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
  }

  /// Firestore Timestamps as DateTime, so the parsers stay free of Firestore types.
  static Map<String, dynamic> _plain(Map<String, dynamic> data) => {
        for (final e in data.entries) e.key: e.value is Timestamp ? (e.value as Timestamp).toDate().toUtc() : e.value,
      };
}
