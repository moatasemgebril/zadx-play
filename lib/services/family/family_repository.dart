import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/child_profile.dart';
import 'firestore_family_repository.dart';
import '../../data/models/plan.dart';

/// Snapshot of a child's day that both the child and parent devices share.
class FamilyDay {
  const FamilyDay({
    required this.day,
    required this.progress,
    required this.usedMinutes,
    required this.prayerLock,
    this.earnedMinutes = 0,
    this.requiredDone = false,
    this.prayerLockSinceMs,
    this.approved,
    this.prayerLockAtMs,
  });

  final String day; // yyyy-MM-dd in the family's city
  final Map<String, Map<String, dynamic>> progress; // taskId -> TaskProgress json
  final int usedMinutes;
  final bool prayerLock;

  /// Derived values written for other devices (Windows guard, parent dashboard).
  final int earnedMinutes;
  final bool requiredDone;

  /// When the current prayer lock started (UTC ms). Free plans end the lock automatically
  /// after the prayer window, measured from this time.
  final int? prayerLockSinceMs;

  /// Server-only credits {taskId: minutes}, written by the `approveTask` Cloud Function after it
  /// checked that the caller is a parent device (R-32). Null for a local-only family, where the
  /// approval stays on this device. Never written by the app to Firestore.
  final Map<String, int>? approved;

  /// Server time (UTC ms) the current prayer lock reached Firestore (`prayerLockAt`). The rules
  /// let a child device end a lock only after the prayer window counted from this time.
  final int? prayerLockAtMs;

  Map<String, dynamic> toJson() => {
        'earnedMinutes': earnedMinutes,
        'requiredDone': requiredDone,
        'day': day,
        'progress': progress,
        'usedMinutes': usedMinutes,
        'prayerLock': prayerLock,
        if (prayerLockSinceMs != null) 'prayerLockSinceMs': prayerLockSinceMs,
        if (approved != null) 'approved': approved,
        if (prayerLockAtMs != null) 'prayerLockAtMs': prayerLockAtMs,
      };

  factory FamilyDay.fromJson(Map<String, dynamic> j) => FamilyDay(
        day: j['day'] as String,
        progress: (j['progress'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map))),
        usedMinutes: j['usedMinutes'] as int? ?? 0,
        prayerLock: j['prayerLock'] as bool? ?? false,
        earnedMinutes: j['earnedMinutes'] as int? ?? 0,
        requiredDone: j['requiredDone'] as bool? ?? false,
        prayerLockSinceMs: j['prayerLockSinceMs'] as int?,
        approved: parseCredits(j['approved']),
        prayerLockAtMs: j['prayerLockAtMs'] as int?,
      );

  /// {taskId: minutes} from server data; malformed entries are dropped. Null when absent.
  static Map<String, int>? parseCredits(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, int>{};
    raw.forEach((k, v) {
      if (k is String && v is num && v >= 0) out[k] = v.toInt();
    });
    return out;
  }
}

/// The server refused an approval for good (not a parent device, bad input, ...): do not retry.
class ApprovalRejected implements Exception {
  const ApprovalRejected(this.code);
  final String code;
  @override
  String toString() => 'ApprovalRejected($code)';
}

/// The plan `verifyPurchase` (backend/functions/src/index.ts) stores on families/{id}:
/// `plan` ('basic' | 'plus'), `planExpiresAt` (ISO-8601 string), `inTrial` (bool).
/// These fields are server-only (firestore.rules) and readable by every family member,
/// so a child device gets the plan the parent paid for on another phone.
///
/// Fails closed: an unknown plan, or a plan without a readable expiry, is Free.
Entitlement parseFamilyEntitlement(Map<String, dynamic> data, {DateTime Function()? now}) {
  final tier = parsePlanTier(data['plan']);
  final raw = data['planExpiresAt'];
  final expiresAt = switch (raw) {
    String s => DateTime.tryParse(s)?.toUtc(),
    DateTime d => d.toUtc(),
    _ => null,
  };
  if (tier == null || expiresAt == null) return Entitlement(now: now);
  return Entitlement(tier: tier, expiresAt: expiresAt, inTrial: data['inTrial'] == true, now: now);
}

/// Syncs a child's day between the child device and the parent device(s).
///
/// [LocalFamilyRepository] keeps everything on one device (good for demos and
/// single-device families). [FirestoreFamilyRepository] syncs via Firebase.
abstract class FamilyRepository {
  /// Remote changes (e.g. a parent approval). Emits nothing for local-only.
  /// [day] is the date in the family's city (yyyy-MM-dd).
  Stream<FamilyDay> watchDay(String childId, String day);

  /// The family's server-written plan ([parseFamilyEntitlement]), emitted only for snapshots
  /// confirmed by the server (never from the offline cache: offline, the app relies on the
  /// EntitlementCache grace instead). Emits nothing for local-only.
  Stream<Entitlement> watchEntitlement();

  /// Saves this device's part of the day: submissions (`progress`), used minutes and, when
  /// [lockChanged], the prayer lock state. Never the server-only credits (`approved`,
  /// `earnedMinutes`, `requiredDone`): those come from [approveTask].
  Future<void> saveDay(String childId, FamilyDay day, {bool lockChanged = false});

  /// True when approvals and minute credits are decided by the server ([approveTask]), i.e. the
  /// family is synced. False for a local-only family: the approval stays on this device.
  bool get serverApprovals;

  /// Parent device only (the server checks the role): approves [taskId] for [childId] on [day]
  /// and credits [minutes] once, within the daily cap. Throws [ApprovalRejected] when the server
  /// refuses for good; any other error is transient (offline): the caller queues and retries.
  Future<void> approveTask({
    required String childId,
    required String day,
    required String taskId,
    required int minutes,
    required List<String> requiredTaskIds,
    required bool isPrayer,
  });

  /// Parent device only: sends a submission back to "todo". Same errors as [approveTask].
  Future<void> rejectTask({required String childId, required String day, required String taskId});

  /// Settings other devices need (city, method, controlled games for Windows Guard).
  Future<void> saveSettings(Map<String, Object?> settings);

  /// Push notification to the parent devices (handled server-side).
  Future<void> notifyParent(String childId, String type, {Map<String, Object?> data = const {}});

  /// Child profile (nickname + built-in avatar only) shared with the family's devices.
  Future<void> saveChild(ChildProfile child);

  /// Deletes a child's profile and synced days.
  Future<void> deleteChild(String childId);

  /// Tamper alert heartbeat (docs/decisions/DEVICE-PROTECTION.md): reason codes only, e.g.
  /// `accessibility_off`. The backend alerts the parent devices once per new reason.
  Future<void> reportProtection(String childId, {required String platform, required List<String> reasons});
}

class LocalFamilyRepository implements FamilyRepository {
  final _controller = StreamController<FamilyDay>.broadcast();

  @override
  Stream<FamilyDay> watchDay(String childId, String day) => _controller.stream;

  @override
  Stream<Entitlement> watchEntitlement() => const Stream<Entitlement>.empty();

  @override
  Future<void> saveDay(String childId, FamilyDay day, {bool lockChanged = false}) async {}

  @override
  bool get serverApprovals => false;

  @override
  Future<void> approveTask({
    required String childId,
    required String day,
    required String taskId,
    required int minutes,
    required List<String> requiredTaskIds,
    required bool isPrayer,
  }) async {}

  @override
  Future<void> rejectTask({required String childId, required String day, required String taskId}) async {}

  @override
  Future<void> saveSettings(Map<String, Object?> settings) async {}

  @override
  Future<void> notifyParent(String childId, String type, {Map<String, Object?> data = const {}}) async {}

  @override
  Future<void> saveChild(ChildProfile child) async {}

  @override
  Future<void> deleteChild(String childId) async {}

  @override
  Future<void> reportProtection(String childId, {required String platform, required List<String> reasons}) async {}
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
