/// Device-wide lock rules. Decision record: docs/decisions/DEVICE-WIDE-LOCK.md
library;

/// What the native blockers lock.
enum LockMode {
  /// Lock every app except the always-allowed core (phone, emergency, Zad X, launcher, keyboard,
  /// settings, SMS/contacts if allowed) and the parent's allow-list. Default.
  allApps,

  /// Legacy: lock only the games the parent selected.
  selectedGames;

  static LockMode parse(String? value) =>
      LockMode.values.firstWhere((m) => m.name == value, orElse: () => LockMode.allApps);
}

/// Android packages that are never locked. Must match `LockRules.ALWAYS_ALLOWED` in
/// android/app/src/main/kotlin/com/zadx/app/LockRules.kt. Device-specific roles (default dialer,
/// launcher, keyboard, SMS app) are resolved natively by `AllowedApps.kt`.
const Set<String> androidAlwaysAllowed = {
  'android',
  'com.android.systemui',
  'com.android.settings',
  'com.android.phone',
  'com.android.server.telecom',
  'com.android.incallui',
  'com.samsung.android.incallui',
  'com.android.emergency',
  'com.google.android.apps.safetyhub',
  'com.android.cellbroadcastreceiver',
  'com.google.android.cellbroadcastreceiver',
  'com.android.permissioncontroller',
  'com.google.android.permissioncontroller',
  'com.google.android.gms',
};

/// Reference implementation of `LockRules.isControlled` (Kotlin) so the rule is unit-tested in Dart.
/// Returns true when [pkg] must be locked (and meters play minutes when unlocked).
bool lockRuleControls({
  required String pkg,
  required String ownPackage,
  required LockMode mode,
  required Set<String> selectedGames,
  required Set<String> parentAllowed,
  Set<String> systemAllowed = const {},
}) {
  if (pkg.isEmpty || pkg == ownPackage) return false;
  if (mode != LockMode.allApps) return selectedGames.contains(pkg);
  if (androidAlwaysAllowed.contains(pkg) || systemAllowed.contains(pkg)) return false;
  return !parentAllowed.contains(pkg);
}
