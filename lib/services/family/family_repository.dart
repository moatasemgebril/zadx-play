import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/child_profile.dart';
import 'firestore_family_repository.dart';

/// Snapshot of a child's day that both the child and parent devices share.
class FamilyDay {
  const FamilyDay({
    required this.day,
    required this.progress,
    required this.usedMinutes,
    required this.prayerLock,
    this.earnedMinutes = 0,
    this.requiredDone = false,
  });

  final String day; // yyyy-MM-dd in the family's city
  final Map<String, Map<String, dynamic>> progress; // taskId -> TaskProgress json
  final int usedMinutes;
  final bool prayerLock;

  /// Derived values written for other devices (Windows guard, parent dashboard).
  final int earnedMinutes;
  final bool requiredDone;

  Map<String, dynamic> toJson() => {
        'earnedMinutes': earnedMinutes,
        'requiredDone': requiredDone,
        'day': day,
        'progress': progress,
        'usedMinutes': usedMinutes,
        'prayerLock': prayerLock,
      };

  factory FamilyDay.fromJson(Map<String, dynamic> j) => FamilyDay(
        day: j['day'] as String,
        progress: (j['progress'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))),
        usedMinutes: j['usedMinutes'] as int? ?? 0,
        prayerLock: j['prayerLock'] as bool? ?? false,
        earnedMinutes: j['earnedMinutes'] as int? ?? 0,
        requiredDone: j['requiredDone'] as bool? ?? false,
      );
}

/// Syncs a child's day between the child device and the parent device(s).
///
/// [LocalFamilyRepository] keeps everything on one device (good for demos and
/// single-device families). [FirestoreFamilyRepository] syncs via Firebase.
abstract class FamilyRepository {
  /// Remote changes (e.g. a parent approval). Emits nothing for local-only.
  /// [day] is the date in the family's city (yyyy-MM-dd).
  Stream<FamilyDay> watchDay(String childId, String day);

  Future<void> saveDay(String childId, FamilyDay day);

  /// Settings other devices need (city, method, controlled games for Windows Guard).
  Future<void> saveSettings(Map<String, Object?> settings);

  /// Push notification to the parent devices (handled server-side).
  Future<void> notifyParent(String childId, String type, {Map<String, Object?> data = const {}});

  /// Child profile (nickname + built-in avatar only) shared with the family's devices.
  Future<void> saveChild(ChildProfile child);

  /// Deletes a child's profile and synced days.
  Future<void> deleteChild(String childId);
}

class LocalFamilyRepository implements FamilyRepository {
  final _controller = StreamController<FamilyDay>.broadcast();

  @override
  Stream<FamilyDay> watchDay(String childId, String day) => _controller.stream;

  @override
  Future<void> saveDay(String childId, FamilyDay day) async {}

  @override
  Future<void> saveSettings(Map<String, Object?> settings) async {}

  @override
  Future<void> notifyParent(String childId, String type, {Map<String, Object?> data = const {}}) async {}

  @override
  Future<void> saveChild(ChildProfile child) async {}

  @override
  Future<void> deleteChild(String childId) async {}
}

/// True when Firebase initialised (overridden in main()).
final firebaseReadyProvider = Provider<bool>((_) => false);

/// The family this device belongs to. Changes when the device is paired.
final familyIdProvider = StateProvider<String?>((_) => null);

final familyRepositoryProvider = Provider<FamilyRepository>((ref) {
  final id = ref.watch(familyIdProvider);
  if (ref.watch(firebaseReadyProvider) && id != null) return FirestoreFamilyRepository(familyId: id);
  return LocalFamilyRepository();
});

// The active child id lives in children_controller.dart (`activeChildIdProvider`).
