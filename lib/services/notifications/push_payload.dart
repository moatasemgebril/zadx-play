/// Pure parsing / eligibility rules for parent push notifications (no Firebase imports,
/// so they are unit-tested in test/push_payload_test.dart).
///
/// The server sends generic text plus opaque ids only (backend/functions/src/push.ts);
/// this side re-validates the data before acting on it.
library;

enum ParentPushType { taskSubmitted, unlockRequest, adhan, devicePaired, weeklySummary }

const _wireTypes = {
  'task_submitted': ParentPushType.taskSubmitted,
  'unlock_request': ParentPushType.unlockRequest,
  'adhan': ParentPushType.adhan,
  'device_paired': ParentPushType.devicePaired,
  'weekly_summary': ParentPushType.weeklySummary,
};

const _prayers = {'fajr', 'dhuhr', 'asr', 'maghrib', 'isha'};
const _pairTargets = {'phone', 'windows'};
final _idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

String? _id(Object? v) => v is String && _idRe.hasMatch(v) ? v : null;
String? _oneOf(Object? v, Set<String> allowed) => v is String && allowed.contains(v) ? v : null;

/// A validated push payload. Unknown types and malformed ids are rejected / dropped.
class ParentPush {
  const ParentPush({required this.type, this.childId, this.taskId, this.prayer, this.target});

  final ParentPushType type;
  final String? childId;
  final String? taskId;
  final String? prayer;
  final String? target;

  /// Parses FCM `RemoteMessage.data`. Returns null when the type is unknown.
  static ParentPush? fromData(Map<String, dynamic> data) {
    final type = _wireTypes[data['type']];
    if (type == null) return null;
    return ParentPush(
      type: type,
      childId: _id(data['childId']),
      taskId: _id(data['taskId']),
      prayer: _oneOf(data['prayer'], _prayers),
      target: _oneOf(data['target'], _pairTargets),
    );
  }
}

/// Push is offered only on a configured, mobile, PARENT device (never a paired child device).
bool canUseParentPush({
  required bool firebaseReady,
  required bool isMobile,
  required bool isBoundChildDevice,
  required bool hasFamily,
}) =>
    firebaseReady && isMobile && !isBoundChildDevice && hasFamily;

/// Language stored with the token so the server picks AR or EN copy.
String pushLangFor(String language) => language == 'en' ? 'en' : 'ar';
