import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/app_config.dart';
import '../../data/models/child_profile.dart';
import '../../data/models/plan.dart';

/// Free plan = ONE child (owner decision 2026-11-21, docs/decisions/FREE-ONE-CHILD.md).
///
/// When a family with more children (for example added during the 7-day trial) is on Free:
/// * the "free child" stays active: the one the parent chose (PIN-protected), otherwise the
///   first child (oldest created, `child-1` for migrated families);
/// * every other child is PAUSED, never deleted: wallet, tasks, adhkar progress and settings
///   are kept on the device and in Firestore;
/// * paused children become active again by themselves as soon as the plan includes
///   [AppFeature.multipleChildren] (Basic, Plus, a verified store trial or the device trial).
///
/// The same rule runs on the server (`childPaused` in backend/functions/src/security.ts).
@immutable
class ChildPause {
  const ChildPause({required this.freeChildId, this.pausedIds = const {}});

  /// The child that stays active on Free.
  final String freeChildId;

  /// Children that are paused right now (empty on paid plans).
  final Set<String> pausedIds;

  bool get anyPaused => pausedIds.isNotEmpty;

  bool isPaused(String childId) => pausedIds.contains(childId);

  @override
  bool operator ==(Object other) =>
      other is ChildPause && other.freeChildId == freeChildId && setEquals(other.pausedIds, pausedIds);

  @override
  int get hashCode => Object.hash(freeChildId, Object.hashAllUnordered(pausedIds));
}

/// The child that stays active on Free: [chosen] when it still exists, otherwise the first
/// child in creation order (the list order on the parent device; `child-1` comes first).
String freeChildIdOf(List<ChildProfile> children, String? chosen) {
  if (chosen != null && children.any((c) => c.id == chosen)) return chosen;
  return children.isEmpty ? ChildProfile.defaultId : children.first.id;
}

/// Pure rule for a parent (or single shared) device.
ChildPause childPauseFor({
  required List<ChildProfile> children,
  required bool multipleChildrenAllowed,
  String? chosenFreeChildId,
}) {
  final free = freeChildIdOf(children, chosenFreeChildId);
  if (multipleChildrenAllowed) return ChildPause(freeChildId: free);
  return ChildPause(freeChildId: free, pausedIds: {for (final c in children) if (c.id != free) c.id});
}

/// The child a shared/parent device shows: a paused child is never shown, the free child is.
String effectiveActiveChildId({required String selected, required ChildPause pause}) =>
    pause.isPaused(selected) ? pause.freeChildId : selected;

/// What a paired child device knows about the family's plan: the server-written fields of
/// `families/{id}` (plan, expiry, creation time, chosen free child). The child device has no
/// purchase of its own, so this is how it learns that the family is Free or subscribed.
@immutable
class FamilyPlanStatus {
  const FamilyPlanStatus({this.plan, this.planExpiresAt, this.createdAt, this.freeChildId});

  final PlanTier? plan;
  final DateTime? planExpiresAt;

  /// When the family was created (server time). The server counts its 7-day trial from here.
  final DateTime? createdAt;

  /// Chosen by the parent through the `setFreeChild` function; null = `child-1`.
  final String? freeChildId;

  bool paidActive(DateTime now) => plan != null && planExpiresAt != null && planExpiresAt!.isAfter(now);

  bool trialActive(DateTime now) =>
      createdAt != null && now.isBefore(createdAt!.add(const Duration(days: AppConfig.trialDays)));

  /// Same rule as `childPaused` in backend/functions/src/security.ts.
  bool childPaused(String childId, DateTime now) {
    if (paidActive(now) || trialActive(now)) return false;
    final free = freeChildId != null && ChildProfile.isValidId(freeChildId!) ? freeChildId! : ChildProfile.defaultId;
    return childId != free;
  }

  /// Reads `families/{id}` data. Anything malformed is treated as missing (never as paid).
  static FamilyPlanStatus fromFamilyDoc(Map<String, dynamic> d) {
    DateTime? time(Object? v) => switch (v) {
          final String s => DateTime.tryParse(s)?.toUtc(),
          final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
          final DateTime t => t.toUtc(),
          _ => null,
        };
    final free = d['freeChildId'];
    return FamilyPlanStatus(
      plan: parsePlanTier(d['plan']),
      planExpiresAt: time(d['planExpiresAt']),
      createdAt: time(d['createdAt']),
      freeChildId: free is String && ChildProfile.isValidId(free) ? free : null,
    );
  }

  String encode() => jsonEncode({
        if (plan != null) 'plan': plan!.name,
        if (planExpiresAt != null) 'planExpiresAt': planExpiresAt!.toUtc().toIso8601String(),
        if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
        if (freeChildId != null) 'freeChildId': freeChildId,
      });

  static FamilyPlanStatus? tryDecode(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw);
      return j is Map<String, dynamic> ? fromFamilyDoc(j) : null;
    } on FormatException {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FamilyPlanStatus &&
      other.plan == plan &&
      other.planExpiresAt == planExpiresAt &&
      other.createdAt == createdAt &&
      other.freeChildId == freeChildId;

  @override
  int get hashCode => Object.hash(plan, planExpiresAt, createdAt, freeChildId);
}
