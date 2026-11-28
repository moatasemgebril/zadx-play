/// Pure family-core decisions for the zero-cost backend (Spark plan, no Cloud Functions;
/// docs/ZERO-COST-BACKEND.md). They used to run in Cloud Functions (backend/functions/src:
/// `applyApproval`, `removeDeviceDecision`, `isApprovalDay`); now the parent device runs them
/// inside a Firestore transaction and backend/firestore.rules enforces the same limits, so a
/// modified app still cannot credit more, credit twice, act as a child device, or remove the last
/// parent. No Firebase imports: unit-tested in test/family_core_logic_test.dart.
library;

/// Most minutes one approved task can earn (rules: `credit <= 120`).
const int approvalMaxTaskMinutes = 120;

/// Most minutes a child can earn in one day (rules: `earned <= 600`).
const int approvalDailyCapMinutes = 600;

/// Most required tasks one approval may name.
const int approvalMaxTasks = 50;

final RegExp _taskIdRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _safeIdRe = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
final RegExp _dayRe = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isTaskId(String id) => _taskIdRe.hasMatch(id);

/// Firestore-safe id (uids, family ids, audit ids).
bool isSafeId(String id) => _safeIdRe.hasMatch(id);

/// yyyy-MM-dd that is a real date within [maxDays] of [now] (time zones and queued approvals).
/// Same rule as `isApprovalDay` in backend/functions/src/security.ts.
bool isApprovalDay(String value, DateTime now, {int maxDays = 2}) {
  if (!_dayRe.hasMatch(value)) return false;
  final t = DateTime.tryParse('${value}T12:00:00Z');
  if (t == null) return false;
  final iso = t.toIso8601String();
  if (iso.substring(0, 10) != value) return false; // e.g. 2026-02-30
  return t.difference(now.toUtc()).abs() <= Duration(hours: maxDays * 24 + 12);
}

/// Server credits {taskId: minutes} on a day doc; anything malformed is dropped.
Map<String, int> readCredits(Object? raw) {
  final out = <String, int>{};
  if (raw is! Map) return out;
  raw.forEach((k, v) {
    if (k is String && isTaskId(k) && v is int && v >= 0 && v <= approvalMaxTaskMinutes) out[k] = v;
  });
  return out;
}

/// The result of one approval, computed from the day doc read in the same transaction.
class ApprovalOutcome {
  const ApprovalOutcome({
    required this.credit,
    required this.added,
    required this.earnedMinutes,
    required this.requiredDone,
  });

  /// The value stored at `approved.{taskId}` (the old one when the task was already approved).
  final int credit;

  /// Minutes this approval adds (0 when already approved or the daily cap is reached).
  final int added;

  final int earnedMinutes;
  final bool requiredDone;
}

/// Idempotent: a task is credited at most once a day; the day total never goes above
/// [approvalDailyCapMinutes]. `earnedMinutes` grows by exactly [ApprovalOutcome.added] from the
/// stored value (that is what the rules check). requiredDone = every required task has a credit.
ApprovalOutcome applyApproval({
  required Object? approvedBefore,
  required Object? earnedBefore,
  required String taskId,
  required int minutes,
  required List<String> requiredTaskIds,
}) {
  final approved = readCredits(approvedBefore);
  final earned = earnedBefore is int && earnedBefore >= 0 ? earnedBefore : 0;
  final raw = approvedBefore is Map ? approvedBefore[taskId] : null;
  final int credit;
  final int added;
  if (raw is int) {
    // Already approved today: keep the stored credit (the rules refuse any change).
    credit = raw;
    added = 0;
  } else {
    final room = approvalDailyCapMinutes - earned;
    credit = room <= 0 ? 0 : (minutes < room ? minutes : room);
    added = credit;
  }
  approved[taskId] = credit;
  return ApprovalOutcome(
    credit: credit,
    added: added,
    earnedMinutes: earned + added,
    requiredDone: requiredTaskIds.every(approved.containsKey),
  );
}

/// Reason an approval request is refused before any write, or null when it is valid.
String? approvalRequestError({
  required String day,
  required String taskId,
  required int minutes,
  required List<String> requiredTaskIds,
  required DateTime now,
}) {
  if (!isApprovalDay(day, now)) return 'invalid-argument';
  if (!isTaskId(taskId)) return 'invalid-argument';
  if (minutes < 0 || minutes > approvalMaxTaskMinutes) return 'invalid-argument';
  if (requiredTaskIds.length > approvalMaxTasks || !requiredTaskIds.every(isTaskId)) return 'invalid-argument';
  return null;
}

/// How many times the child did [taskId] (progress.{taskId}.count), 0 when malformed.
int progressCount(Object? progress, String taskId) {
  if (progress is! Map) return 0;
  final entry = progress[taskId];
  if (entry is! Map) return 0;
  final count = entry['count'];
  return count is int && count >= 0 && count <= 10000 ? count : 0;
}

/// Role of a family member, from the family doc only (same rule as `isParent` in the rules).
enum MemberRole { parent, child }

MemberRole? memberRoleOf(Map<String, dynamic> family, String uid) {
  final members = family['members'];
  if (members is! List || !members.contains(uid)) return null;
  final kids = family['childDevices'];
  return kids is Map && kids[uid] is String ? MemberRole.child : MemberRole.parent;
}

int parentMemberCount(Map<String, dynamic> family) {
  final members = family['members'];
  if (members is! List) return 0;
  return members.whereType<String>().toSet().where((m) => memberRoleOf(family, m) == MemberRole.parent).length;
}

/// May [callerUid] remove [targetUid]? Returns the target's role, or the refusal reason the UI
/// knows (`not_member`, `parent_required`, `device_not_found`, `last_parent`). The rules check
/// the same things again on the server.
({MemberRole? role, String? reason}) removeDeviceDecision(Map<String, dynamic> family, String callerUid, String targetUid) {
  final caller = memberRoleOf(family, callerUid);
  if (caller == null) return (role: null, reason: 'not_member');
  if (caller != MemberRole.parent) return (role: null, reason: 'parent_required');
  final target = memberRoleOf(family, targetUid);
  if (target == null || !isSafeId(targetUid)) return (role: null, reason: 'device_not_found');
  if (target == MemberRole.parent && parentMemberCount(family) <= 1) return (role: null, reason: 'last_parent');
  return (role: target, reason: null);
}
