import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/settings_controller.dart';

/// Star balance for the built-in Zad X learning games.
///
/// Stars are earned by finishing rounds (Quran Letters, Heroes of the Prophets)
/// and spent in Build Your Mosque. They are a separate, purely cosmetic
/// currency: stars never add play minutes and never touch the wallet, so the
/// game-time lock cannot be bypassed through these games.
///
/// Invariants: the balance is never negative, earning or spending a
/// non-positive amount is ignored, and a spend larger than the balance fails
/// without changing anything.
class StarsController extends Notifier<int> {
  static const prefsKey = 'edu.stars.balance';

  /// Upper bound on one award, so a bug in a game can't flood the balance.
  static const maxAwardPerRound = 10;

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);

  @override
  int build() {
    final stored = _prefs.getInt(prefsKey) ?? 0;
    return stored < 0 ? 0 : stored;
  }

  /// Adds [amount] stars (ignored when [amount] <= 0, capped per call).
  void earn(int amount) {
    if (amount <= 0) return;
    final add = amount > maxAwardPerRound ? maxAwardPerRound : amount;
    _set(state + add);
  }

  /// Removes [amount] stars. Returns false (and changes nothing) when
  /// [amount] <= 0 or the balance is too small.
  bool spend(int amount) {
    if (amount <= 0 || amount > state) return false;
    _set(state - amount);
    return true;
  }

  bool canAfford(int amount) => amount > 0 && amount <= state;

  void _set(int value) {
    final v = value < 0 ? 0 : value;
    state = v;
    _prefs.setInt(prefsKey, v);
  }
}

final starsProvider = NotifierProvider<StarsController, int>(StarsController.new);
