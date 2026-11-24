import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/child_profile.dart';

/// SharedPreferences layout for per-child data, plus the one-time migration
/// from the single-child layout (v1) to the multi-child layout (v2).
///
/// v1: `wallet.state`, `wallet.state.tasks`, `adhkar.counts`
/// v2: `children.list`, `children.active`, `children.bound`,
///     `wallet.child.<id>.state`, `wallet.child.<id>.tasks`, `adhkar.child.<id>.counts`
///
/// Learning games (stars, mosque, letters) were shared by all children until
/// 2026-11-22 (`edu.stars.balance`, `edu.mosque.built`, `edu.letters.best`);
/// they now live under `edu.child.<id>.*` and [migrateEdu] moves the old shared
/// values to the active child once.
class ChildStorage {
  const ChildStorage._();

  static const legacyWalletKey = 'wallet.state';
  static const legacyTasksKey = 'wallet.state.tasks';
  static const legacyAdhkarKey = 'adhkar.counts';

  static const childrenKey = 'children.list';
  static const activeKey = 'children.active';

  /// Set on a child's device after pairing: the device belongs to this child only.
  static const boundKey = 'children.bound';

  /// The child the parent keeps active on the Free plan (docs/decisions/FREE-ONE-CHILD.md).
  static const freeChildKey = 'children.free';

  /// The free child the server last confirmed (`setFreeChild`); absent = `child-1`.
  static const freeChildSyncedKey = 'children.freeSynced';

  /// Child device: cached server-written plan fields of the family.
  static const familyStatusKey = 'family.planStatus';

  static String walletKey(String childId) => 'wallet.child.$childId.state';
  static String tasksKey(String childId) => 'wallet.child.$childId.tasks';
  static String adhkarKey(String childId) => 'adhkar.child.$childId.counts';

  static const legacyEduStarsKey = 'edu.stars.balance';
  static const legacyEduMosqueKey = 'edu.mosque.built';
  static const legacyEduLettersKey = 'edu.letters.best';

  static String eduStarsKey(String childId) => 'edu.child.$childId.stars.balance';
  static String eduMosqueKey(String childId) => 'edu.child.$childId.mosque.built';
  static String eduLettersKey(String childId) => 'edu.child.$childId.letters.best';

  /// Returns the stored children, migrating v1 data into a default child the
  /// first time. Safe to call repeatedly (idempotent) and never throws on
  /// corrupted data.
  static List<ChildProfile> migrate(SharedPreferences prefs) {
    final existing = readChildren(prefs);
    if (existing != null && existing.isNotEmpty) return existing;

    const first = ChildProfile(id: ChildProfile.defaultId, nickname: '');
    _move(prefs, legacyWalletKey, walletKey(first.id));
    _move(prefs, legacyTasksKey, tasksKey(first.id));
    _move(prefs, legacyAdhkarKey, adhkarKey(first.id));
    writeChildren(prefs, const [first]);
    prefs.setString(activeKey, first.id);
    return const [first];
  }

  static List<ChildProfile>? readChildren(SharedPreferences prefs) {
    final raw = prefs.getString(childrenKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final seen = <String>{};
      return [
        for (final e in decoded)
          if (ChildProfile.tryFromJson(e) case final c? when seen.add(c.id)) c,
      ];
    } on FormatException {
      return null;
    }
  }

  static void writeChildren(SharedPreferences prefs, List<ChildProfile> children) {
    prefs.setString(childrenKey, jsonEncode(children.map((c) => c.toJson()).toList()));
  }

  /// Removes everything stored on this device for [childId].
  static void deleteChildData(SharedPreferences prefs, String childId) {
    prefs
      ..remove(walletKey(childId))
      ..remove(tasksKey(childId))
      ..remove(adhkarKey(childId))
      ..remove(eduStarsKey(childId))
      ..remove(eduMosqueKey(childId))
      ..remove(eduLettersKey(childId));
  }

  /// One-time move of the shared (pre per-child) learning-game progress to
  /// [childId], normally the active child the first time a game loads (on a
  /// paired child device that is the child it belongs to). All three values move
  /// together so they always land on the same child. Idempotent: the shared keys
  /// are deleted afterwards, and a child that already has its own value keeps it.
  static void migrateEdu(SharedPreferences prefs, String childId) {
    final stars = prefs.get(legacyEduStarsKey);
    if (stars is int && !prefs.containsKey(eduStarsKey(childId))) prefs.setInt(eduStarsKey(childId), stars);
    final built = prefs.get(legacyEduMosqueKey);
    if (built is int && !prefs.containsKey(eduMosqueKey(childId))) prefs.setInt(eduMosqueKey(childId), built);
    final best = prefs.get(legacyEduLettersKey);
    if (best is List && !prefs.containsKey(eduLettersKey(childId))) {
      prefs.setStringList(eduLettersKey(childId), [for (final e in best) e.toString()]);
    }
    for (final k in const [legacyEduStarsKey, legacyEduMosqueKey, legacyEduLettersKey]) {
      if (prefs.containsKey(k)) prefs.remove(k);
    }
  }

  /// Copies [from] to [to] (unless [to] already has data), then deletes [from].
  static void _move(SharedPreferences prefs, String from, String to) {
    final value = prefs.getString(from);
    if (value == null) return;
    if (prefs.getString(to) == null) prefs.setString(to, value);
    prefs.remove(from);
  }
}
