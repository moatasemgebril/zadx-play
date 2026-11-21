package com.zadx.app

/**
 * Pure lock rules (no Android types) so they can be reasoned about and unit-tested.
 * Mirrored in Dart by `lockRuleControls()` in lib/services/app_lock/lock_rules.dart — keep both in sync.
 * Decision record: docs/decisions/DEVICE-WIDE-LOCK.md
 */
object LockRules {
    /** Lock every app except the always-allowed core and the parent's allow-list. */
    const val MODE_ALL_APPS = "allApps"

    /** Legacy: lock only the games the parent selected. */
    const val MODE_SELECTED_GAMES = "selectedGames"

    /**
     * System packages that must never be locked (phone/emergency, system UI, dialogs, permissions,
     * settings). Device-specific roles (default dialer, launcher, keyboard, SMS) are resolved at
     * runtime by [AllowedApps].
     */
    val ALWAYS_ALLOWED: Set<String> = setOf(
        "android", // system dialogs, app chooser
        "com.android.systemui", // notification shade, lock screen, recents on some devices
        "com.android.settings",
        "com.android.phone", // telephony + emergency dialer
        "com.android.server.telecom",
        "com.android.incallui",
        "com.samsung.android.incallui",
        "com.android.emergency", // emergency information
        "com.google.android.apps.safetyhub", // Personal Safety
        "com.android.cellbroadcastreceiver", // emergency alerts
        "com.google.android.cellbroadcastreceiver",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.google.android.gms", // Google sign-in / account / Find My Device sheets
    )

    /**
     * @param pkg foreground package
     * @param ownPackage Zad X's package (never locked)
     * @param mode [MODE_ALL_APPS] or [MODE_SELECTED_GAMES] (anything else = legacy)
     * @param selectedGames packages of the games chosen by the parent (legacy mode)
     * @param parentAllowed packages the parent explicitly allowed (allApps mode)
     * @param systemAllowed device roles resolved on-device (dialer, launcher, IME, SMS, contacts…)
     */
    fun isControlled(
        pkg: String,
        ownPackage: String,
        mode: String,
        selectedGames: Set<String>,
        parentAllowed: Set<String>,
        systemAllowed: Set<String>,
    ): Boolean {
        if (pkg.isEmpty() || pkg == ownPackage) return false
        if (mode != MODE_ALL_APPS) return pkg in selectedGames
        if (pkg in ALWAYS_ALLOWED || pkg in systemAllowed) return false
        return pkg !in parentAllowed
    }
}
