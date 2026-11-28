import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'pin_security.dart';

/// Offline parent PIN recovery (BACKLOG P1 "no PIN recovery").
///
/// When the parent creates the PIN, Zad X makes a one-time recovery code
/// (`XXXX-XXXX-XXXX`, 12 characters from an alphabet without look-alikes, about 59 bits),
/// shows it once and keeps only a salted PBKDF2 hash ([PinSecurity.hashPin]). The code
/// resets a forgotten PIN; every reset issues a new code and the old one stops working.
///
/// A store-account / e-mail reset is a later step, once Firebase is live.
class RecoveryCode {
  RecoveryCode._();

  /// No 0/O, 1/I/L: easy to copy by hand and read back.
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const length = 12;
  static const groupSize = 4;

  /// A new random code, grouped as `XXXX-XXXX-XXXX`. Uses [Random.secure] with rejection
  /// sampling, so every character is equally likely.
  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    final limit = 256 - (256 % alphabet.length); // reject bytes that would bias the result
    final chars = <String>[];
    while (chars.length < length) {
      final b = r.nextInt(256);
      if (b < limit) chars.add(alphabet[b % alphabet.length]);
    }
    return format(chars.join());
  }

  /// `ABCDEFGHJKMN` → `ABCD-EFGH-JKMN`.
  static String format(String normalized) {
    final groups = <String>[];
    for (var i = 0; i < normalized.length; i += groupSize) {
      groups.add(normalized.substring(i, min(i + groupSize, normalized.length)));
    }
    return groups.join('-');
  }

  /// What the parent typed → the 12 code characters (upper case, no dashes or spaces), or
  /// null when it cannot be a code.
  static String? normalize(String input) {
    final s = input.toUpperCase().replaceAll(RegExp(r'[\s\-–—_.]'), '');
    if (s.length != length) return null;
    for (final ch in s.split('')) {
      if (!alphabet.contains(ch)) return null;
    }
    return s;
  }

  /// The characters the parent types to confirm they wrote the code down.
  static String lastFour(String code) {
    final n = normalize(code) ?? code;
    return n.substring(n.length - 4);
  }

  /// Salted, slow hash for storage (same PBKDF2 as the PIN). Never store the plain code.
  static String hash(String code, {int rounds = PinSecurity.iterations}) {
    final n = normalize(code);
    if (n == null) throw ArgumentError('not a recovery code');
    return PinSecurity.hashPin('zadx-recovery:$n', rounds: rounds);
  }

  /// True when [input] is the code behind [stored]. Only the salted PBKDF2 format is
  /// accepted (never the legacy unsalted PIN format).
  static bool verify(String input, String stored) {
    final n = normalize(input);
    if (n == null || PinSecurity.needsUpgrade(stored)) return false;
    return PinSecurity.verifyPin('zadx-recovery:$n', stored);
  }

  /// Lock-out after [failures] wrong recovery codes. Stricter than the PIN: none for the first
  /// [freeAttempts], then 60 s doubling each time, capped at 1 hour.
  static const freeAttempts = 3;
  static Duration lockoutFor(int failures) {
    if (failures < freeAttempts) return Duration.zero;
    final step = min(failures - freeAttempts, 6); // 1, 2, 4, 8, 16, 32, 60 min
    return Duration(seconds: min(60 * (1 << step), 3600));
  }

  static Duration get maxLockout => lockoutFor(1000);
}

enum RecoveryResult { ok, wrong, locked, noCode }

/// Recovery-code hash and its wrong-try counter, in shared preferences (persisted, so
/// restarting the app does not reset the lock-out).
class PinRecoveryStore {
  PinRecoveryStore(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const hashKey = 'parent.recoveryHash';
  static const failuresKey = 'parent.recoveryFailures';
  static const lockedUntilKey = 'parent.recoveryLockedUntil';

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  bool get hasCode => _prefs.getString(hashKey) != null;

  /// Seconds left in the current lock-out (0 when a code may be tried). A lock-out longer than
  /// the maximum means the clock was moved back: it is kept at the maximum.
  int lockSecondsLeft() {
    final until = _prefs.getInt(lockedUntilKey) ?? 0;
    final left = (until - _now().millisecondsSinceEpoch).clamp(0, RecoveryCode.maxLockout.inMilliseconds);
    return (left / 1000).ceil();
  }

  /// Checks [input]. Wrong codes count towards the lock-out; nothing is changed on success
  /// (the old code stays valid until [commit] stores the new one, so abandoning the reset
  /// half-way never leaves the parent without a code).
  RecoveryResult check(String input) {
    final stored = _prefs.getString(hashKey);
    if (stored == null) return RecoveryResult.noCode;
    if (lockSecondsLeft() > 0) return RecoveryResult.locked;
    if (RecoveryCode.verify(input, stored)) {
      _prefs.remove(failuresKey);
      _prefs.remove(lockedUntilKey);
      return RecoveryResult.ok;
    }
    final failures = (_prefs.getInt(failuresKey) ?? 0) + 1;
    _prefs.setInt(failuresKey, failures);
    final lock = RecoveryCode.lockoutFor(failures);
    if (lock > Duration.zero) {
      _prefs.setInt(lockedUntilKey, _now().add(lock).millisecondsSinceEpoch);
    }
    return lock > Duration.zero ? RecoveryResult.locked : RecoveryResult.wrong;
  }

  /// Stores the hash of [code] and invalidates any older code.
  Future<void> commit(String code, {int rounds = PinSecurity.iterations}) async {
    await _prefs.setString(hashKey, RecoveryCode.hash(code, rounds: rounds));
    await _prefs.remove(failuresKey);
    await _prefs.remove(lockedUntilKey);
  }
}
