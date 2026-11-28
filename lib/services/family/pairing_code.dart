import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Pairing codes for the zero-cost backend (Spark plan, no Cloud Functions; see
/// docs/ZERO-COST-BACKEND.md).
///
/// There is no server to rate-limit guesses, so the code itself must be unguessable inside its
/// 10-minute life: 10 symbols from a 31-symbol alphabet without look-alikes (no 0/O, 1/I/L) =
/// 31^10 ≈ 8.2 × 10^14 codes (≈ 49.5 bits), made with [Random.secure]. The code is shown as
/// `XXXXX-XXXXX` and never stored: Firestore keeps it under `pairingCodes/{docId}` where
/// [docId] is a SHA-256 of the code, so knowing the doc id is the proof of knowing the code. The
/// rules allow `get` of one code doc (never `list`), only while it is live.
abstract final class PairingCode {
  /// 31 symbols: digits 2–9 and A–Z without I, L and O.
  static const alphabet = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

  static const length = 10;

  /// Same life as the rules (`codeLive` in backend/firestore.rules), counted from server time.
  static const ttl = Duration(minutes: 10);

  /// A new random code (canonical form, no dash).
  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return String.fromCharCodes(List<int>.generate(length, (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length))));
  }

  /// What a parent or child typed → the canonical code, or null when it cannot be one.
  /// Case-insensitive; spaces and dashes are ignored; Arabic-Indic and Persian digits count as
  /// the same digits.
  static String? normalize(String input) {
    final buf = StringBuffer();
    for (final rune in input.toUpperCase().runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buf.writeCharCode(0x30 + rune - 0x0660); // ٠..٩
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buf.writeCharCode(0x30 + rune - 0x06F0); // ۰..۹
      } else if (rune == 0x20 || rune == 0x2D || rune == 0x2010 || rune == 0x2011 || rune == 0x2013) {
        continue; // space and dashes
      } else {
        buf.writeCharCode(rune);
      }
    }
    final s = buf.toString();
    if (s.length != length) return null;
    for (final c in s.codeUnits) {
      if (!alphabet.codeUnits.contains(c)) return null;
    }
    return s;
  }

  /// `ABCDE-FGHJK`: easier to read aloud and to type.
  static String display(String code) =>
      code.length == length ? '${code.substring(0, 5)}-${code.substring(5)}' : code;

  /// Firestore doc id of [code] (canonical form): lowercase hex SHA-256 with a version prefix.
  static String docId(String code) => sha256.convert(utf8.encode('zadx-pair-v1:$code')).toString();

  /// Doc ids as the rules accept them (`isCodeId`).
  static bool isDocId(String id) => RegExp(r'^[0-9a-f]{64}$').hasMatch(id);
}

/// What a pairing code doc says (`pairingCodes/{docId}`); null fields = malformed doc.
class PairingCodeInfo {
  const PairingCodeInfo({required this.familyId, required this.target, this.childId});

  final String familyId;

  /// `phone` (child device), `parent` (another parent phone) or `windows` (Zad X Guard).
  final String target;

  /// The child a phone / windows code binds to; null for a parent code.
  final String? childId;

  bool get isParent => target == 'parent';

  static const targets = {'phone', 'parent', 'windows'};

  static PairingCodeInfo? tryParse(Map<String, dynamic>? data) {
    if (data == null) return null;
    final familyId = data['familyId'];
    final target = data['target'];
    final childId = data['childId'];
    if (familyId is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(familyId)) return null;
    if (target is! String || !targets.contains(target)) return null;
    if (target == 'parent') return PairingCodeInfo(familyId: familyId, target: target);
    if (childId is! String || !RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(childId)) return null;
    return PairingCodeInfo(familyId: familyId, target: target, childId: childId);
  }
}

/// A pairing code was refused for good (`invalid_code`, `parent_link_family_in_use`, ...).
class PairingRejected implements Exception {
  const PairingRejected(this.reason);
  final String reason;
  @override
  String toString() => 'PairingRejected($reason)';
}
