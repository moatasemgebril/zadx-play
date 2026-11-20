import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/features/parent/pin_security.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('PBKDF2-HMAC-SHA256 matches published test vectors', () {
    expect(
      _hex(PinSecurity.pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 1, 32)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      _hex(PinSecurity.pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 4096, 32)),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );
    expect(
      _hex(PinSecurity.pbkdf2Sha256(
        utf8.encode('passwordPASSWORDpassword'),
        utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
        4096,
        40,
      )),
      '348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9',
    );
  });

  test('hashPin is salted and verifies', () {
    final a = PinSecurity.hashPin('1234', rounds: 100);
    final b = PinSecurity.hashPin('1234', rounds: 100);
    expect(a, isNot(b));
    expect(PinSecurity.verifyPin('1234', a), isTrue);
    expect(PinSecurity.verifyPin('1235', a), isFalse);
    expect(PinSecurity.needsUpgrade(a), isFalse);
  });

  test('legacy unsalted hashes still verify and are flagged for upgrade', () {
    final legacy = PinSecurity.legacyHash('4321');
    expect(PinSecurity.verifyPin('4321', legacy), isTrue);
    expect(PinSecurity.verifyPin('0000', legacy), isFalse);
    expect(PinSecurity.needsUpgrade(legacy), isTrue);
  });

  test('malformed stored values never verify', () {
    expect(PinSecurity.verifyPin('1234', r'pbkdf2-sha256$x$AAAA$AAAA'), isFalse);
    expect(PinSecurity.verifyPin('1234', r'pbkdf2-sha256$100$@@@$AAAA'), isFalse);
    expect(PinSecurity.verifyPin('1234', ''), isFalse);
  });

  test('lock-out grows after repeated failures and is capped', () {
    expect(PinSecurity.lockoutFor(4), Duration.zero);
    expect(PinSecurity.lockoutFor(5), const Duration(seconds: 30));
    expect(PinSecurity.lockoutFor(6), const Duration(seconds: 60));
    expect(PinSecurity.lockoutFor(100), const Duration(minutes: 15));
  });
}
