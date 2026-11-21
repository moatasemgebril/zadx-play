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
  'com.samsung.android.emergency',
  'com.sec.android.app.safetyassurance',
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
  // Safety core + device roles first, in every mode.
  if (androidAlwaysAllowed.contains(pkg) || systemAllowed.contains(pkg)) return false;
  if (mode != LockMode.allApps) return selectedGames.contains(pkg);
  return !parentAllowed.contains(pkg);
}

// -------------------------------------------------------------------------------------------------
// Device protection (owner decision 2026-11-21, docs/decisions/DEVICE-PROTECTION.md).
// Mirrors `LockRules.protectionGuard` / `tamperReasons` in LockRules.kt — keep both in sync.
// -------------------------------------------------------------------------------------------------

/// Why the protection layer covers a window on Android.
enum ProtectionGuard { none, settings, uninstall }

/// Settings surfaces locked for the child (plus the package resolved from ACTION_SETTINGS on the device).
const Set<String> androidSettingsPackages = {
  'com.android.settings',
  'com.android.settings.intelligence',
  'com.google.android.settings.intelligence',
  'com.samsung.android.settings.intelligence',
  'com.samsung.android.app.settings.bixby',
  'com.miui.securitycenter',
};

/// System installers that show the uninstall confirmation.
const Set<String> androidPackageInstallers = {
  'com.android.packageinstaller',
  'com.google.android.packageinstaller',
  'com.samsung.android.packageinstaller',
};

/// Longest parent window the PIN can open (the parent area asks for [parentWindowMinutes]).
const int maxParentWindowMinutes = 10;
const int parentWindowMinutes = 5;

/// Reference implementation of `LockRules.protectionGuard` (Kotlin).
ProtectionGuard protectionGuardFor({
  required String pkg,
  String? className,
  required String ownPackage,
  required bool settingsLock,
  required bool uninstallGuard,
  required bool parentWindowOpen,
  Set<String> resolvedSettings = const {},
}) {
  if (pkg.isEmpty || pkg == ownPackage || parentWindowOpen) return ProtectionGuard.none;
  if (androidAlwaysAllowed.contains(pkg) && !androidSettingsPackages.contains(pkg)) return ProtectionGuard.none;
  if (settingsLock && (androidSettingsPackages.contains(pkg) || resolvedSettings.contains(pkg))) {
    return ProtectionGuard.settings;
  }
  final uninstallUi = androidPackageInstallers.contains(pkg) &&
      className != null &&
      className.toLowerCase().contains('uninstall');
  if (uninstallGuard && uninstallUi) return ProtectionGuard.uninstall;
  return ProtectionGuard.none;
}

/// Protection state reported by the native layer (`protectionStatus`). Never contains app names.
class ProtectionStatus {
  const ProtectionStatus({
    required this.platform,
    this.accessibility = false,
    this.serviceEverEnabled = false,
    this.deviceAdmin = false,
    this.adminEverEnabled = false,
    this.authorization = false,
    this.authorizationEverApproved = false,
    this.windowSeconds = 0,
  });

  final String platform; // android | ios | none
  final bool accessibility;
  final bool serviceEverEnabled;
  final bool deviceAdmin;
  final bool adminEverEnabled;
  final bool authorization;
  final bool authorizationEverApproved;
  final int windowSeconds;

  static const none = ProtectionStatus(platform: 'none');

  factory ProtectionStatus.fromMap(Object? raw) {
    if (raw is! Map) return none;
    bool b(String k) => raw[k] == true;
    return ProtectionStatus(
      platform: raw['platform'] is String ? raw['platform'] as String : 'none',
      accessibility: b('accessibility'),
      serviceEverEnabled: b('serviceEverEnabled'),
      deviceAdmin: b('deviceAdmin'),
      adminEverEnabled: b('adminEverEnabled'),
      authorization: b('authorization'),
      authorizationEverApproved: b('authorizationEverApproved'),
      windowSeconds: raw['windowSeconds'] is int ? raw['windowSeconds'] as int : 0,
    );
  }

  /// True once protection was set up on this device (only then is anything reported).
  bool get wasSetUp => serviceEverEnabled || authorizationEverApproved;
}

/// Tamper reasons sent to the backend (mirror of `LockRules.tamperReasons` + the iOS check).
/// Only a protection that was on before counts, so a half-finished setup never alerts the parent.
List<String> protectionTamperReasons(ProtectionStatus s, {required bool uninstallGuard}) => [
      if (s.serviceEverEnabled && !s.accessibility) 'accessibility_off',
      if (uninstallGuard && s.adminEverEnabled && !s.deviceAdmin) 'device_admin_off',
      if (s.authorizationEverApproved && !s.authorization) 'screen_time_off',
    ];
