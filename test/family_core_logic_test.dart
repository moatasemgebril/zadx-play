// Zero-cost backend (Spark plan, no Cloud Functions; docs/ZERO-COST-BACKEND.md): the pure
// family-core decisions the parent device now runs before its rules-checked Firestore writes.
// The rules re-check the same limits (backend/functions/test/rules.test.js).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/services/family/device_removal.dart';
import 'package:zadx/services/family/family_core_logic.dart';
import 'package:zadx/services/family/pairing_code.dart';

void main() {
  group('PairingCode', () {
    test('10 symbols from the 31-symbol alphabet, no look-alikes', () {
      expect(PairingCode.alphabet.length, 31);
      for (final c in ['0', 'O', '1', 'I', 'L']) {
        expect(PairingCode.alphabet.contains(c), isFalse, reason: c);
      }
      final r = Random(7);
      for (var i = 0; i < 200; i++) {
        final code = PairingCode.generate(r);
        expect(code.length, PairingCode.length);
        expect(PairingCode.normalize(code), code);
      }
    });

    test('keyspace is large enough without a server rate limit (> 2^49)', () {
      expect(pow(PairingCode.alphabet.length, PairingCode.length), greaterThan(pow(2, 49)));
    });

    test('normalize: case, dashes, spaces and Arabic-Indic digits', () {
      expect(PairingCode.normalize('abcde-fghjk'), 'ABCDEFGHJK');
      expect(PairingCode.normalize(' AB CDE–FGH JK '), 'ABCDEFGHJK');
      expect(PairingCode.normalize('٢٣٤٥٦-ABCDE'), '23456ABCDE');
      expect(PairingCode.normalize('۲۳۴۵۶ABCDE'), '23456ABCDE');
      expect(PairingCode.normalize('123456'), isNull); // old 6-digit codes
      expect(PairingCode.normalize('ABCDEFGHJ0'), isNull); // 0 is not in the alphabet
      expect(PairingCode.normalize('ABCDEFGHJKM'), isNull); // too long
      expect(PairingCode.normalize(''), isNull);
    });

    test('display groups 5-5', () {
      expect(PairingCode.display('ABCDEFGHJK'), 'ABCDE-FGHJK');
    });

    test('doc id is a stable lowercase sha256 hex the rules accept', () {
      final id = PairingCode.docId('ABCDEFGHJK');
      expect(PairingCode.isDocId(id), isTrue);
      expect(id, PairingCode.docId('ABCDEFGHJK'));
      expect(id, isNot(PairingCode.docId('ABCDEFGHJM')));
      expect(id.contains('ABCDEFGHJK'), isFalse);
    });

    test('PairingCodeInfo parses only well-formed code docs', () {
      expect(PairingCodeInfo.tryParse({'familyId': 'f1', 'target': 'phone', 'childId': 'c1'})?.childId, 'c1');
      expect(PairingCodeInfo.tryParse({'familyId': 'f1', 'target': 'parent'})?.isParent, isTrue);
      expect(PairingCodeInfo.tryParse({'familyId': 'f1', 'target': 'phone'}), isNull); // no child
      expect(PairingCodeInfo.tryParse({'familyId': 'f/1', 'target': 'parent'}), isNull);
      expect(PairingCodeInfo.tryParse({'familyId': 'f1', 'target': 'admin'}), isNull);
      expect(PairingCodeInfo.tryParse(null), isNull);
    });
  });

  group('applyApproval (mirror of the rules: once, 0..120, 600 a day)', () {
    test('first approval credits the minutes and adds them to earnedMinutes', () {
      final out = applyApproval(
        approvedBefore: {'prayer': 10},
        earnedBefore: 10,
        taskId: 'homework',
        minutes: 20,
        requiredTaskIds: const ['prayer', 'homework'],
      );
      expect(out.credit, 20);
      expect(out.added, 20);
      expect(out.earnedMinutes, 30);
      expect(out.requiredDone, isTrue);
    });

    test('a second approval of the same task adds nothing and keeps the stored credit', () {
      final out = applyApproval(
        approvedBefore: {'homework': 20},
        earnedBefore: 20,
        taskId: 'homework',
        minutes: 90,
        requiredTaskIds: const ['room'],
      );
      expect(out.credit, 20);
      expect(out.added, 0);
      expect(out.earnedMinutes, 20);
      expect(out.requiredDone, isFalse);
    });

    test('the daily cap limits the credit', () {
      final out = applyApproval(
        approvedBefore: const {},
        earnedBefore: 590,
        taskId: 'room',
        minutes: 60,
        requiredTaskIds: const [],
      );
      expect(out.credit, 10);
      expect(out.earnedMinutes, approvalDailyCapMinutes);
      final full = applyApproval(
        approvedBefore: const {},
        earnedBefore: 600,
        taskId: 'extra',
        minutes: 60,
        requiredTaskIds: const [],
      );
      expect(full.credit, 0);
      expect(full.earnedMinutes, 600);
    });

    test('request validation', () {
      final now = DateTime.utc(2026, 11, 28, 12);
      String? err({String day = '2026-11-28', String task = 'room', int minutes = 10, List<String> req = const []}) =>
          approvalRequestError(day: day, taskId: task, minutes: minutes, requiredTaskIds: req, now: now);
      expect(err(), isNull);
      expect(err(minutes: approvalMaxTaskMinutes + 1), 'invalid-argument');
      expect(err(minutes: -1), 'invalid-argument');
      expect(err(task: 'a/b'), 'invalid-argument');
      expect(err(day: '2026-11-20'), 'invalid-argument'); // too old
      expect(err(day: '2026-02-30'), 'invalid-argument'); // not a date
      expect(err(req: List<String>.filled(approvalMaxTasks + 1, 'x')), 'invalid-argument');
    });

    test('progressCount reads only sane counts', () {
      expect(progressCount({'room': {'status': 'pending', 'count': 2}}, 'room'), 2);
      expect(progressCount({'room': {'count': -1}}, 'room'), 0);
      expect(progressCount(null, 'room'), 0);
    });
  });

  group('removeDeviceDecision (mirror of the rules)', () {
    final family = <String, dynamic>{
      'members': ['p1', 'p2', 'k1'],
      'childDevices': {'k1': 'c1'},
    };

    test('a parent removes a child device or another parent', () {
      expect(removeDeviceDecision(family, 'p1', 'k1').role, MemberRole.child);
      expect(removeDeviceDecision(family, 'p1', 'p2').role, MemberRole.parent);
      expect(removeDeviceDecision(family, 'p1', 'p1').role, MemberRole.parent); // not the last parent
    });

    test('refusals', () {
      expect(removeDeviceDecision(family, 'k1', 'p1').reason, 'parent_required');
      expect(removeDeviceDecision(family, 'x', 'k1').reason, 'not_member');
      expect(removeDeviceDecision(family, 'p1', 'nobody').reason, 'device_not_found');
      final onlyParent = <String, dynamic>{
        'members': ['p1', 'k1'],
        'childDevices': {'k1': 'c1'},
      };
      expect(removeDeviceDecision(onlyParent, 'p1', 'p1').reason, 'last_parent');
    });
  });

  group('membershipFromFirestore (two explicit answers needed, offline = unknown)', () {
    test('readable family listing this uid = member', () {
      expect(membershipFromFirestore(uid: 'u', familyMembers: const ['u', 'p']), MembershipProbe.member);
      expect(membershipFromFirestore(uid: 'u', familyMembers: const ['p']), MembershipProbe.unknown);
    });

    test('refused family + own removal marker = not a member; no marker = unknown', () {
      expect(membershipFromFirestore(uid: 'u', removedMarker: true), MembershipProbe.notMember);
      expect(membershipFromFirestore(uid: 'u', removedMarker: false), MembershipProbe.unknown);
      expect(membershipFromFirestore(uid: 'u'), MembershipProbe.unknown);
    });
  });
}
