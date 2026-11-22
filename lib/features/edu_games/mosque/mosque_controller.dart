import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/catalog/mosque_parts.dart';
import '../../../services/family/child_storage.dart';
import '../../../services/family/children_controller.dart';
import '../../settings/settings_controller.dart';
import '../stars_controller.dart';

enum BuildResult { built, notEnoughStars, complete }

/// How many mosque parts are built. Parts are always added in the order of
/// [mosqueParts], so the state is just a count (persisted per child,
/// [ChildStorage.eduMosqueKey]).
class MosqueController extends Notifier<int> {
  /// The old count shared by all children; moved to the active child once
  /// by [ChildStorage.migrateEdu].
  static const prefsKey = ChildStorage.legacyEduMosqueKey;

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);
  String _key = ChildStorage.eduMosqueKey('child-1');

  @override
  int build() {
    final childId = ref.watch(activeChildIdProvider);
    ChildStorage.migrateEdu(_prefs, childId);
    _key = ChildStorage.eduMosqueKey(childId);
    final stored = _prefs.getInt(_key) ?? 0;
    if (stored < 0) return 0;
    return stored > mosqueParts.length ? mosqueParts.length : stored;
  }

  bool get isComplete => state >= mosqueParts.length;

  /// The next part to build, or null when the mosque is complete.
  MosquePart? get nextPart => isComplete ? null : mosqueParts[state];

  /// Spends stars on the next part. Nothing changes unless it succeeds.
  BuildResult buildNext() {
    final part = nextPart;
    if (part == null) return BuildResult.complete;
    if (!ref.read(starsProvider.notifier).spend(part.cost)) return BuildResult.notEnoughStars;
    state = state + 1;
    _prefs.setInt(_key, state);
    return BuildResult.built;
  }
}

final mosqueProvider = NotifierProvider<MosqueController, int>(MosqueController.new);
