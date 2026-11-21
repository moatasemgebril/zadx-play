import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/services/notifications/push_payload.dart';

void main() {
  test('parses every server push type', () {
    expect(ParentPush.fromData({'type': 'task_submitted'})!.type, ParentPushType.taskSubmitted);
    expect(ParentPush.fromData({'type': 'unlock_request'})!.type, ParentPushType.unlockRequest);
    expect(ParentPush.fromData({'type': 'adhan'})!.type, ParentPushType.adhan);
    expect(ParentPush.fromData({'type': 'device_paired'})!.type, ParentPushType.devicePaired);
    expect(ParentPush.fromData({'type': 'weekly_summary'})!.type, ParentPushType.weeklySummary);
  });

  test('unknown or missing type is ignored', () {
    expect(ParentPush.fromData({}), isNull);
    expect(ParentPush.fromData({'type': 'marketing'}), isNull);
    expect(ParentPush.fromData({'type': 42}), isNull);
  });

  test('keeps valid ids and enum values', () {
    final p = ParentPush.fromData({
      'type': 'unlock_request',
      'childId': 'child-1',
      'taskId': 'prayer_task',
      'prayer': 'asr',
    })!;
    expect(p.childId, 'child-1');
    expect(p.taskId, 'prayer_task');
    expect(p.prayer, 'asr');
    expect(p.target, isNull);
    expect(ParentPush.fromData({'type': 'device_paired', 'target': 'windows'})!.target, 'windows');
  });

  test('drops free text, path tricks and bad enum values', () {
    final p = ParentPush.fromData({
      'type': 'task_submitted',
      'childId': '../families/x',
      'taskId': "Omar's homework",
      'prayer': 'party',
      'target': 'console',
    })!;
    expect(p.childId, isNull);
    expect(p.taskId, isNull);
    expect(p.prayer, isNull);
    expect(p.target, isNull);
    expect(ParentPush.fromData({'type': 'adhan', 'childId': 'x' * 65})!.childId, isNull);
  });

  test('push only on a configured mobile parent device in a family', () {
    bool can({bool fb = true, bool mobile = true, bool child = false, bool family = true}) =>
        canUseParentPush(firebaseReady: fb, isMobile: mobile, isBoundChildDevice: child, hasFamily: family);
    expect(can(), isTrue);
    expect(can(fb: false), isFalse); // CI / no google-services files
    expect(can(mobile: false), isFalse); // web, Windows, macOS
    expect(can(child: true), isFalse); // paired child device: never
    expect(can(family: false), isFalse);
  });

  test('token language is ar unless en', () {
    expect(pushLangFor('en'), 'en');
    expect(pushLangFor('ar'), 'ar');
    expect(pushLangFor('fr'), 'ar');
  });
}
