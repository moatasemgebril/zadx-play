import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Parent PIN storage and brute-force throttling.
///
/// Stored format: `pbkdf2-sha256$<iterations>$<salt base64>$<hash base64>`.
/// Hashes written by older versions (`sha256('zadx:<pin>')`, no salt) are still accepted
/// once and should then be replaced with [hashPin] by the caller.
class PinSecurity {
  PinSecurity._();

  static const iterations = 20000;
  static const _prefix = 'pbkdf2-sha256';

  /// Failed attempts allowed before the gate starts locking.
  static const freeAttempts = 5;

  /// Shared-preferences keys of the wrong-PIN counter and lock-out end (shared by every PIN
  /// prompt; cleared after a successful recovery-code reset).
  static const failuresKey = 'parent.pinFailures';
  static const lockedUntilKey = 'parent.pinLockedUntil';

  /// Salted, slow hash of [pin] for storage.
  static String hashPin(String pin, {List<int>? salt, int rounds = iterations}) {
    final s = salt ?? _randomBytes(16);
    final dk = pbkdf2Sha256(utf8.encode(pin), s, rounds, 32);
    return '$_prefix\$$rounds\$${base64Encode(s)}\$${base64Encode(dk)}';
  }

  /// True when [pin] matches [stored] (new or legacy format). Constant-time comparison.
  static bool verifyPin(String pin, String stored) {
    final parts = stored.split(r'$');
    if (parts.length == 4 && parts[0] == _prefix) {
      final rounds = int.tryParse(parts[1]);
      if (rounds == null || rounds < 1 || rounds > 1000000) return false;
      final salt = _tryBase64(parts[2]);
      final expected = _tryBase64(parts[3]);
      if (salt == null || expected == null || expected.isEmpty) return false;
      return _constantTimeEquals(pbkdf2Sha256(utf8.encode(pin), salt, rounds, expected.length), expected);
    }
    // Legacy unsalted format.
    return _constantTimeEquals(utf8.encode(legacyHash(pin)), utf8.encode(stored));
  }

  /// True when [stored] uses the old unsalted format and should be re-hashed.
  static bool needsUpgrade(String stored) => !stored.startsWith('$_prefix\$');

  static String legacyHash(String pin) => sha256.convert(utf8.encode('zadx:$pin')).toString();

  /// Lock-out after [failures] consecutive wrong PINs: none for the first [freeAttempts],
  /// then 30 s doubling each time, capped at 15 minutes.
  static Duration lockoutFor(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final step = min(failures - freeAttempts, 5); // 30s, 60s, 120s, 240s, 480s, 900s
    return Duration(seconds: min(30 * (1 << step), 900));
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018).
  static Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int rounds, int length) {
    final hmac = Hmac(sha256, password);
    final out = <int>[];
    var block = 1;
    while (out.length < length) {
      final blockIndex = Uint8List(4)..buffer.asByteData().setUint32(0, block);
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < rounds; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
      block++;
    }
    return Uint8List.fromList(out.sublist(0, length));
  }

  static List<int>? _tryBase64(String s) {
    try {
      return base64Decode(s);
    } on FormatException {
      return null;
    }
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }
}
