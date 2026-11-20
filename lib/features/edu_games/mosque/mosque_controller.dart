import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/catalog/mosque_parts.dart';
import '../../settings/settings_controller.dart';
import '../stars_controller.dart';

enum BuildResult { built, notEnoughStars, complete }

/// How many mosque parts are built. Parts are always added in the order of
/// [mosqueParts], so the state is just a count (persisted).
class MosqueController extends Notifier<int> {
  static const prefsKey = 'edu.mosque.built';

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  int build() {
    final stored = _prefs.getInt(prefsKey) ?? 0;
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
    _prefs.setInt(prefsKey, state);
    return BuildResult.built;
  }
}

final mosqueProvider = NotifierProvider<MosqueController, int>(MosqueController.new);
