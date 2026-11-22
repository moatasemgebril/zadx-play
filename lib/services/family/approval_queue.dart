import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'family_repository.dart';

/// One parent decision waiting to reach the server (`approveTask` / `rejectTask`).
@immutable
class PendingApproval {
  const PendingApproval({
    required this.approve,
    required this.familyId,
    required this.childId,
    required this.day,
    required this.taskId,
    this.minutes = 0,
    this.requiredTaskIds = const [],
    this.isPrayer = false,
  });

  final bool approve;
  final String familyId;
  final String childId;
  final String day;
  final String taskId;
  final int minutes;
  final List<String> requiredTaskIds;
  final bool isPrayer;

  bool sameTarget(PendingApproval o) =>
      familyId == o.familyId && childId == o.childId && day == o.day && taskId == o.taskId;

  Map<String, dynamic> toJson() => {
        'approve': approve,
        'familyId': familyId,
        'childId': childId,
        'day': day,
        'taskId': taskId,
        'minutes': minutes,
        'requiredTaskIds': requiredTaskIds,
        'isPrayer': isPrayer,
      };

  static PendingApproval? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final ids = j['requiredTaskIds'];
    if (j['familyId'] is! String || j['childId'] is! String || j['day'] is! String || j['taskId'] is! String) {
      return null;
    }
    return PendingApproval(
      approve: j['approve'] == true,
      familyId: j['familyId'] as String,
      childId: j['childId'] as String,
      day: j['day'] as String,
      taskId: j['taskId'] as String,
      minutes: (j['minutes'] as num?)?.toInt() ?? 0,
      requiredTaskIds: ids is List ? ids.whereType<String>().toList() : const [],
      isPrayer: j['isPrayer'] == true,
    );
  }
}

/// Offline-first approvals on the PARENT device: a decision taken while offline is kept here
/// and sent to the server (which checks the parent role and credits the minutes) once online.
/// The child device never uses this: it can only submit.
class ApprovalQueue {
  ApprovalQueue(this._prefs);

  final SharedPreferences _prefs;
  static const storageKey = 'family.approvalQueue';
  static const maxItems = 100;
  static bool _flushing = false;

  List<PendingApproval> read() {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      return list.map(PendingApproval.fromJson).whereType<PendingApproval>().toList();
    } on FormatException {
      return [];
    }
  }

  void _write(List<PendingApproval> items) {
    if (items.isEmpty) {
      _prefs.remove(storageKey);
    } else {
      _prefs.setString(storageKey, jsonEncode(items.map((e) => e.toJson()).toList()));
    }
  }

  /// The latest decision for a task replaces an older queued one (approve after reject, ...).
  void add(PendingApproval item) {
    final items = read().where((e) => !e.sameTarget(item)).toList()..add(item);
    _write(items.length > maxItems ? items.sublist(items.length - maxItems) : items);
  }

  void _remove(PendingApproval item) =>
      _write(read().where((e) => !(e.sameTarget(item) && e.approve == item.approve)).toList());

  /// Sends one decision now; queues it when offline. Returns false when the server refused it.
  Future<bool> send(FamilyRepository repo, PendingApproval item) async {
    try {
      await _call(repo, item);
      _remove(item);
      return true;
    } on ApprovalRejected catch (e) {
      debugPrint('approval refused: ${e.code}');
      _remove(item);
      return false;
    } catch (e) {
      debugPrint('approval queued (offline?): $e');
      add(item);
      return true;
    }
  }

  /// Sends the queued decisions of [familyId] in order; stops at the first transient error.
  /// Decisions for another family (the phone was re-linked) are dropped.
  Future<void> flush(FamilyRepository repo, String? familyId) async {
    if (_flushing || !repo.serverApprovals) return;
    _flushing = true;
    try {
      for (final item in read()) {
        if (item.familyId != familyId) {
          _remove(item);
          continue;
        }
        try {
          await _call(repo, item);
          _remove(item);
        } on ApprovalRejected catch (e) {
          debugPrint('queued approval refused: ${e.code}');
          _remove(item);
        } catch (_) {
          break; // still offline: keep the rest for later
        }
      }
    } finally {
      _flushing = false;
    }
  }

  static Future<void> _call(FamilyRepository repo, PendingApproval item) => item.approve
      ? repo.approveTask(
          childId: item.childId,
          day: item.day,
          taskId: item.taskId,
          minutes: item.minutes,
          requiredTaskIds: item.requiredTaskIds,
          isPrayer: item.isPrayer,
        )
      : repo.rejectTask(childId: item.childId, day: item.day, taskId: item.taskId);
}
