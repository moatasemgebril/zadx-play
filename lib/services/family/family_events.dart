import 'package:flutter/foundation.dart';

// Parent alerts without a server (owner decision 2026-11-28: zero cost, no Cloud Functions,
// no push). docs/decisions/SPARK-APP-NO-FUNCTIONS.md
//
// * A child device writes one small event doc per alert to `families/{f}/events/{id}`:
//   `{type, childId, at (server time), by (its uid), detail?, reasons?}`. No names, no app
//   names, no usage, no location.
// * A child device keeps `families/{f}/presence/{childId}` up to date: `lastSeen` (server time,
//   at most every `presenceInterval`), `platform`, and the current protection problems.
// * The parent app reads both while it is open or comes back to the foreground: it lists them in
//   the parent area and shows a local notification for new events (`eventsToNotify`) and for a
//   child device that has been silent for over `staleAfter` (this replaces `checkHeartbeats`).

/// Event types a child device writes.
abstract final class FamilyEventType {
  static const taskSubmitted = 'task_submitted';
  static const adhan = 'adhan';
  static const protection = 'protection';

  static const all = {taskSubmitted, adhan, protection};
}

/// Reason codes of a protection problem (mirror of `TAMPER_REASONS` in backend security.ts).
const tamperReasons = {'accessibility_off', 'device_admin_off', 'screen_time_off', 'clock_changed'};

/// A child device writes `lastSeen` at most this often.
const presenceInterval = Duration(minutes: 15);

/// A child device that has not been seen for this long is "not checking in".
const staleAfter = Duration(hours: 24);

/// The parent app lists (and keeps) events of this many days.
const eventRetention = Duration(days: 7);

/// Longest `detail` stored on an event (a task id or a prayer name).
const maxEventDetailLength = 64;

@immutable
class FamilyEvent {
  const FamilyEvent({required this.id, required this.type, required this.childId, this.at, this.detail, this.reasons = const []});

  final String id;
  final String type;
  final String childId;

  /// Server time of the event; null while the server has not stamped it yet.
  final DateTime? at;
  final String? detail;
  final List<String> reasons;

  /// Reads an event doc. Null for anything malformed or of an unknown type (never shown).
  static FamilyEvent? tryParse(String id, Map<String, dynamic> data) {
    final type = data['type'];
    final childId = data['childId'];
    if (type is! String || !FamilyEventType.all.contains(type)) return null;
    if (childId is! String || childId.isEmpty) return null;
    final at = data['at'];
    final detail = data['detail'];
    final reasons = data['reasons'];
    return FamilyEvent(
      id: id,
      type: type,
      childId: childId,
      at: switch (at) {
        final DateTime d => d.toUtc(),
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        _ => null,
      },
      detail: detail is String ? detail : null,
      reasons: reasons is List ? [for (final r in reasons) if (r is String && tamperReasons.contains(r)) r] : const [],
    );
  }
}

/// The fields of a new event doc (without `at` and `by`, which the repository adds).
Map<String, Object?> eventFields(String type, String childId, {String? detail, List<String> reasons = const []}) => {
      'type': type,
      'childId': childId,
      if (detail != null && detail.isNotEmpty)
        'detail': detail.length > maxEventDetailLength ? detail.substring(0, maxEventDetailLength) : detail,
      if (reasons.isNotEmpty) 'reasons': reasons,
    };

/// The `detail` of a `notifyParent` call: the task id or the prayer, nothing else.
String? eventDetailFrom(Map<String, Object?> data) {
  final v = data['taskId'] ?? data['prayer'];
  return v is String ? v : null;
}

/// Known reason codes of [reasons], sorted and without duplicates.
List<String> cleanTamperReasons(Iterable<String> reasons) => (reasons.where(tamperReasons.contains).toSet().toList()..sort());

/// Reasons present now that were not reported last time (each problem is alerted once).
List<String> newTamperReasons(Iterable<String> previous, Iterable<String> current) {
  final before = previous.toSet();
  return [for (final r in current) if (!before.contains(r)) r];
}

/// What the parent app knows about a child device.
@immutable
class ChildPresence {
  const ChildPresence({required this.childId, this.lastSeen, this.protection = const []});

  final String childId;
  final DateTime? lastSeen;

  /// Protection problems the device reported last (empty = all on).
  final List<String> protection;

  /// True when the device has not been seen for over [staleAfter].
  bool isStale(DateTime now) => lastSeen != null && now.toUtc().difference(lastSeen!.toUtc()) > staleAfter;

  static ChildPresence? tryParse(String id, Map<String, dynamic> data) {
    if (id.isEmpty) return null;
    final seen = data['lastSeen'];
    final protection = data['protection'];
    return ChildPresence(
      childId: id,
      lastSeen: switch (seen) {
        final DateTime d => d.toUtc(),
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        _ => null,
      },
      protection: protection is List ? cleanTamperReasons(protection.whereType<String>()) : const [],
    );
  }
}

/// A child device writes `lastSeen` only when the last write is at least [presenceInterval] old
/// (or when it never wrote, or the clock went back).
bool shouldTouchPresence(DateTime? lastWrite, DateTime now) {
  if (lastWrite == null) return true;
  final since = now.difference(lastWrite);
  return since.isNegative || since >= presenceInterval;
}

/// Which notification settings let an event through on the parent phone.
bool eventWanted(FamilyEvent e, {required bool notifyOnTasks, required bool notifyOnAdhan, required bool adhanSupported}) =>
    switch (e.type) {
      FamilyEventType.taskSubmitted => notifyOnTasks,
      FamilyEventType.adhan => adhanSupported && notifyOnAdhan,
      _ => true,
    };

/// Events to show as a local notification: stamped after [notifiedUntil] (the newest event the
/// parent phone already notified), oldest first. Events without a server time wait.
List<FamilyEvent> eventsToNotify(Iterable<FamilyEvent> events, DateTime notifiedUntil) {
  final out = [for (final e in events) if (e.at != null && e.at!.isAfter(notifiedUntil)) e];
  out.sort((a, b) => a.at!.compareTo(b.at!));
  return out;
}

/// Events to list in the parent area: the last [eventRetention], newest first.
List<FamilyEvent> recentEvents(Iterable<FamilyEvent> events, DateTime now) {
  final from = now.toUtc().subtract(eventRetention);
  final out = [for (final e in events) if (e.at != null && e.at!.isAfter(from)) e];
  out.sort((a, b) => b.at!.compareTo(a.at!));
  return out;
}
