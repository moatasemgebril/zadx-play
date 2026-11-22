import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-launch family setup that can never leave an orphan family (Quality Gate on #33).
///
/// Before: start-up called `families.add(...)` under a 5 s timeout. When the timeout fired, the
/// app forgot the id, but Firestore still sent the queued write later, so the family doc was
/// created with nobody pointing at it, and the next start created another one.
///
/// Now:
/// 1. The family id is generated on the device ([newId], no network) and saved in
///    `family.id` together with a `family.pendingCreate` marker, BEFORE any network call.
/// 2. [create] writes that same id. It must be idempotent (FirestoreFamilyRepository.createFamily:
///    `set(merge)` with `members: arrayUnion([uid])`), so running it again after a write that was
///    slow but did land changes nothing.
/// 3. Only when [create] succeeds is the marker removed. A timeout leaves the app local for this
///    session (as before) and the next start retries with the SAME id.
abstract final class FamilyBootstrap {
  static const idKey = 'family.id';
  static const pendingKey = 'family.pendingCreate';

  /// The family id to use this session, or null to run locally this time (offline, slow network).
  static Future<String?> run(
    SharedPreferences prefs, {
    required String Function() newId,
    required Future<String> Function() signIn,
    required Future<void> Function(String familyId, String uid) create,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    var id = prefs.getString(idKey);
    if (id == null) {
      id = newId();
      // Marker first: a crash between the two writes leaves a marker without an id, which the
      // check below clears on the next start.
      await prefs.setString(pendingKey, id);
      await prefs.setString(idKey, id);
    }
    final pending = prefs.getString(pendingKey);
    if (pending != null && pending != id) {
      // The device joined another family (pairing) before its own family was created.
      await prefs.remove(pendingKey);
    }
    try {
      final uid = await signIn().timeout(timeout);
      if (prefs.getString(pendingKey) == id) {
        await create(id, uid).timeout(timeout);
        await prefs.remove(pendingKey);
      }
      return id;
    } catch (e) {
      debugPrint('Family setup not finished, staying local this time: $e');
      return null;
    }
  }
}
