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

  Map<String, dynamic> toJson() => {
        'earnedMinutes': earnedMinutes,
        'requiredDone': requiredDone,
        'day': day,
        'progress': progress,
        'usedMinutes': usedMinutes,
        'prayerLock': prayerLock,
        if (prayerLockSinceMs != null) 'prayerLockSinceMs': prayerLockSinceMs,
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
      );
}

/// What a paired child device writes to its day doc (risk R-32). backend/firestore.rules
/// (`childDayWrite`) lets a child device only:
/// - change ONE task entry per write (named in `childTask`) to `todo` or `pending`, never `done`;
/// - add play time (`usedMinutes` only goes up: sent as an increment);
/// - start a prayer lock (`prayerLock: true` + `prayerLockSinceMs`), never end it.
/// `earnedMinutes`, `requiredDone`, approvals and ending a prayer lock come from parent devices.
class ChildDayPatch {
  const ChildDayPatch({
    required this.day,
    this.usedMinutesDelta = 0,
    this.taskId,
    this.task,
    this.startsPrayerLock = false,
    this.prayerLockSinceMs,
  });

  final String day;

  /// Minutes to add to `usedMinutes` (never negative).
  final int usedMinutesDelta;

  /// The one task entry this write changes, with its new `{status, count}`.
  final String? taskId;
  final Map<String, Object?>? task;

  /// True when this write starts a prayer lock.
  final bool startsPrayerLock;
  final int? prayerLockSinceMs;

  static const _childStatuses = {'todo', 'pending'};

  bool get isEmpty => usedMinutesDelta <= 0 && taskId == null && !startsPrayerLock;

  /// Fields for the day doc, except `usedMinutes` (the repository sends [usedMinutesDelta]
  /// as a server-side increment so it composes with the Windows Guard's own increments).
  Map<String, Object?> toJson() => {
        'day': day,
        if (taskId != null && task != null) ...{
          'childTask': taskId,
          'progress': {taskId!: task},
        },
        if (startsPrayerLock) 'prayerLock': true,
        if (startsPrayerLock && prayerLockSinceMs != null) 'prayerLockSinceMs': prayerLockSinceMs,
      };

  /// The writes a child device makes for a local change from [before] to [after].
  /// Changes a child device may not make (approvals, ending a lock, fewer minutes) stay local:
  /// the parent's devices own them and send them back through `watchDay`.
  static List<ChildDayPatch> between(FamilyDay before, FamilyDay after) {
    final delta = after.usedMinutes - before.usedMinutes;
    final starts = after.prayerLock && !before.prayerLock;
    final taskIds = <String>[
      for (final e in after.progress.entries)
        if (_childStatuses.contains(e.value['status'] ?? 'todo') && !_sameEntry(before.progress[e.key], e.value))
          e.key,
    ]..sort();

    Map<String, Object?> entry(String id) {
      final e = after.progress[id]!;
      final count = e['count'];
      return {'status': e['status'] ?? 'todo', 'count': count is int ? count : 0};
    }

    final first = ChildDayPatch(
      day: after.day,
      usedMinutesDelta: delta > 0 ? delta : 0,
      taskId: taskIds.isEmpty ? null : taskIds.first,
      task: taskIds.isEmpty ? null : entry(taskIds.first),
      startsPrayerLock: starts,
      prayerLockSinceMs: starts ? after.prayerLockSinceMs : null,
    );
    return [
      if (!first.isEmpty) first,
      for (final id in taskIds.skip(1)) ChildDayPatch(day: after.day, taskId: id, task: entry(id)),
    ];
  }

  static bool _sameEntry(Map<String, dynamic>? a, Map<String, dynamic> b) =>
      a != null && (a['status'] ?? 'todo') == (b['status'] ?? 'todo') && (a['count'] ?? 0) == (b['count'] ?? 0);
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

  Future<void> saveDay(String childId, FamilyDay day);

  /// A paired child device's write to its day doc: only what [ChildDayPatch] allows (R-32).
  Future<void> saveChildDay(String childId, ChildDayPatch patch);

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
  Future<void> saveDay(String childId, FamilyDay day) async {}

  @override
  Future<void> saveChildDay(String childId, ChildDayPatch patch) async {}

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
