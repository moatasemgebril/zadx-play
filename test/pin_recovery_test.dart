import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/parent/pin_recovery.dart';
import 'package:zadx/features/parent/pin_security.dart';

/// Offline parent PIN recovery code (BACKLOG P1 "no PIN recovery").
void main() {
  group('RecoveryCode.generate', () {
    test('is XXXX-XXXX-XXXX from the unambiguous alphabet', () {
      final format = RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{4}-[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{4}$');
      for (var i = 0; i < 200; i++) {
        final code = RecoveryCode.generate();
        expect(code, matches(format));
        expect(code, isNot(matches(RegExp('[01ILO]'))));
      }
    });

    test('codes differ and every alphabet character can appear', () {
      final codes = {for (var i = 0; i < 300; i++) RecoveryCode.generate()};
      expect(codes.length, 300);
      final seen = codes.join().replaceAll('-', '').split('').toSet();
      expect(seen, RecoveryCode.alphabet.split('').toSet());
    });

    test('rejection sampling never maps biased bytes', () {
      // A fake source that returns only bytes above the unbiased limit, then valid ones.
      final code = RecoveryCode.generate(_Seq([255, 254, 253, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]));
      expect(RecoveryCode.normalize(code), 'ABCDEFGHJKMN');
    });
  });

  group('RecoveryCode.normalize', () {
    test('accepts lower case, spaces and dashes', () {
      expect(RecoveryCode.normalize('abcd-efgh-jkmn'), 'ABCDEFGHJKMN');
      expect(RecoveryCode.normalize(' ABCD EFGH JKMN '), 'ABCDEFGHJKMN');
    });

    test('rejects wrong length or characters outside the alphabet', () {
      expect(RecoveryCode.normalize('ABCD-EFGH-JKM'), isNull);
      expect(RecoveryCode.normalize('ABCD-EFGH-JKMNP'), isNull);
      expect(RecoveryCode.normalize('ABCD-EFGH-JKM0'), isNull);
      expect(RecoveryCode.normalize('ABCD-EFGH-JKMI'), isNull);
      expect(RecoveryCode.normalize(''), isNull);
    });

    test('lastFour is the last group', () {
      expect(RecoveryCode.lastFour('ABCD-EFGH-JKMN'), 'JKMN');
    });
  });

  group('RecoveryCode.hash / verify', () {
    test('stores a salted PBKDF2 hash, never the plain code', () {
      const code = 'ABCD-EFGH-JKMN';
      final a = RecoveryCode.hash(code, rounds: 50);
      final b = RecoveryCode.hash(code, rounds: 50);
      expect(a, startsWith('pbkdf2-sha256\$50\$'));
      expect(a, isNot(b)); // salted
      expect(a, isNot(contains('ABCD')));
      expect(a, isNot(contains('JKMN')));
      expect(RecoveryCode.verify(code, a), isTrue);
      expect(RecoveryCode.verify('abcd efgh jkmn', a), isTrue);
      expect(RecoveryCode.verify('ABCD-EFGH-JKMP', a), isFalse);
    });

    test('a PIN hash or a legacy unsalted hash never verifies as a recovery code', () {
      expect(RecoveryCode.verify('ABCD-EFGH-JKMN', PinSecurity.hashPin('ABCDEFGHJKMN', rounds: 50)), isFalse);
      expect(RecoveryCode.verify('ABCD-EFGH-JKMN', PinSecurity.legacyHash('ABCDEFGHJKMN')), isFalse);
      expect(RecoveryCode.verify('ABCD-EFGH-JKMN', ''), isFalse);
    });

    test('hash refuses something that is not a code', () {
      expect(() => RecoveryCode.hash('1234'), throwsArgumentError);
    });
  });

  test('recovery lock-out is at least as strict as the PIN lock-out', () {
    expect(RecoveryCode.lockoutFor(2), Duration.zero);
    expect(RecoveryCode.lockoutFor(3), const Duration(minutes: 1));
    expect(RecoveryCode.lockoutFor(4), const Duration(minutes: 2));
    expect(RecoveryCode.lockoutFor(100), const Duration(hours: 1));
    for (var f = 0; f < 30; f++) {
      expect(RecoveryCode.lockoutFor(f), greaterThanOrEqualTo(PinSecurity.lockoutFor(f)), reason: '$f failures');
    }
  });

  group('PinRecoveryStore', () {
    late SharedPreferences prefs;
    var now = DateTime(2026, 11, 28, 9);
    PinRecoveryStore store() => PinRecoveryStore(prefs, now: () => now);

    setUp(() async {
      now = DateTime(2026, 11, 28, 9);
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('no code stored → noCode, and nothing is counted', () {
      expect(store().hasCode, isFalse);
      expect(store().check('ABCD-EFGH-JKMN'), RecoveryResult.noCode);
      expect(prefs.getInt(PinRecoveryStore.failuresKey), isNull);
    });

    test('commit keeps only the hash; the right code verifies', () async {
      await store().commit('ABCD-EFGH-JKMN', rounds: 50);
      expect(store().hasCode, isTrue);
      final saved = prefs.getString(PinRecoveryStore.hashKey)!;
      expect(saved, isNot(contains('ABCD')));
      for (final k in prefs.getKeys()) {
        expect('${prefs.get(k)}', isNot(contains('EFGH')), reason: k);
      }
      expect(store().check('abcd-efgh-jkmn'), RecoveryResult.ok);
    });

    test('a new code invalidates the old one', () async {
      await store().commit('ABCD-EFGH-JKMN', rounds: 50);
      await store().commit('ZYXW-VUTS-RQPN', rounds: 50);
      expect(store().check('ABCD-EFGH-JKMN'), RecoveryResult.wrong);
      expect(store().check('ZYXW-VUTS-RQPN'), RecoveryResult.ok);
    });

    test('wrong codes lock out, even the right code, until the time passes', () async {
      await store().commit('ABCD-EFGH-JKMN', rounds: 50);
      expect(store().check('AAAA-AAAA-AAAA'), RecoveryResult.wrong);
      expect(store().check('AAAA-AAAA-AAAB'), RecoveryResult.wrong);
      expect(store().check('AAAA-AAAA-AAAC'), RecoveryResult.locked);
      expect(store().lockSecondsLeft(), 60);
      expect(store().check('ABCD-EFGH-JKMN'), RecoveryResult.locked); // right code, still locked
      now = now.add(const Duration(seconds: 61));
      expect(store().lockSecondsLeft(), 0);
      expect(store().check('AAAA-AAAA-AAAD'), RecoveryResult.locked); // 4th failure: 2 minutes
      expect(store().lockSecondsLeft(), 120);
      now = now.add(const Duration(minutes: 3));
      expect(store().check('ABCD-EFGH-JKMN'), RecoveryResult.ok);
      expect(prefs.getInt(PinRecoveryStore.failuresKey), isNull); // success resets the counter
    });

    test('a lock-out survives a new store (app restart) and moving the clock back', () async {
      await store().commit('ABCD-EFGH-JKMN', rounds: 50);
      for (var i = 0; i < 3; i++) {
        store().check('AAAA-AAAA-AAAA');
      }
      expect(PinRecoveryStore(prefs, now: () => now).lockSecondsLeft(), 60);
      now = now.subtract(const Duration(days: 365)); // clock moved back a year
      expect(store().lockSecondsLeft(), RecoveryCode.maxLockout.inSeconds);
    });

    test('the lock-out counts badly formatted guesses too', () async {
      await store().commit('ABCD-EFGH-JKMN', rounds: 50);
      store().check('1');
      store().check('');
      expect(store().check('hello'), RecoveryResult.locked);
    });
  });
}

/// Returns the given values in order (for testing rejection sampling).
class _Seq implements Random {
  _Seq(this.values);
  final List<int> values;
  var _i = 0;

  @override
  int nextInt(int max) => values[_i++] % max;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}
