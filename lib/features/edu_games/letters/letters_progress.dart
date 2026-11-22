import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/family/child_storage.dart';
import '../../../services/family/children_controller.dart';
import '../../settings/settings_controller.dart';
import 'letters_quiz.dart';

/// Best stars (0–3) per Quran Letters level, persisted. Level 1 is always
/// open; each next level opens once the previous one has been finished.
/// Stored per child ([ChildStorage.eduLettersKey]).
class LettersProgressController extends Notifier<Map<int, int>> {
  /// The old progress shared by all children; moved to the active child once
  /// by [ChildStorage.migrateEdu].
  static const prefsKey = ChildStorage.legacyEduLettersKey;

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);
  String _key = ChildStorage.eduLettersKey('child-1');

  @override
  Map<int, int> build() {
    final childId = ref.watch(activeChildIdProvider);
    ChildStorage.migrateEdu(_prefs, childId);
    _key = ChildStorage.eduLettersKey(childId);
    final raw = _prefs.getStringList(_key) ?? const <String>[];
    final out = <int, int>{};
    for (final entry in raw) {
      final parts = entry.split(':');
      if (parts.length != 2) continue;
      final level = int.tryParse(parts[0]);
      final stars = int.tryParse(parts[1]);
      if (level == null || stars == null || stars < 0 || stars > 3) continue;
      out[level] = stars;
    }
    return out;
  }

  bool isUnlocked(int level) => level <= 1 || (state[level - 1] ?? 0) > 0;

  void record(int level, int stars) {
    if (stars <= (state[level] ?? 0)) return;
    state = {...state, level: stars};
    _prefs.setStringList(_key, [for (final e in state.entries) '${e.key}:${e.value}']);
  }
}

final lettersProgressProvider =
    NotifierProvider<LettersProgressController, Map<int, int>>(LettersProgressController.new);

LetterLevel letterLevel(int number) => letterLevels.firstWhere((l) => l.number == number, orElse: () => letterLevels.first);
