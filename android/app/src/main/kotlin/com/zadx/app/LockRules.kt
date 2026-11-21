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
        "com.samsung.android.emergency", // Samsung emergency mode
        "com.sec.android.app.safetyassurance", // Samsung Emergency SOS
    )

    // ---------------------------------------------------------------------------------------------
    // Device protection (owner decision 2026-11-21, docs/decisions/DEVICE-PROTECTION.md):
    // the Settings app is for the parent only, and the uninstall dialog is blocked while
    // "Prevent deleting Zad X" is on. Both apply at all times (not only while apps are locked)
    // unless the parent opened a short window with the PIN. They never touch phone/emergency.
    // ---------------------------------------------------------------------------------------------

    /** Why the protection layer covers the foreground window. */
    enum class Guard { NONE, SETTINGS, UNINSTALL }

    /** Longest window the parent PIN can open (Dart asks for 5 minutes). */
    const val MAX_PARENT_WINDOW_MS = 10 * 60_000L

    /**
     * Settings surfaces locked for the child. The device's real Settings package is also resolved at
     * runtime from `Intent(Settings.ACTION_SETTINGS)` (vendor builds may rename it) and passed in as
     * `resolvedSettings`. Settings search ("settings intelligence") opens Settings pages directly.
     * OEM entries must be confirmed on real devices (docs/STORE_CHECKLIST.md device matrix).
     */
    val SETTINGS_PACKAGES: Set<String> = setOf(
        "com.android.settings", // AOSP, Pixel, Samsung One UI, most OEMs
        "com.android.settings.intelligence", // settings search (AOSP)
        "com.google.android.settings.intelligence", // settings search (Pixel)
        "com.samsung.android.settings.intelligence", // settings search (Samsung)
        "com.samsung.android.app.settings.bixby", // Samsung settings suggestions
        "com.miui.securitycenter", // Xiaomi app info / uninstall / permissions
    )

    /** System package installers that show the "uninstall this app?" dialog. */
    val PACKAGE_INSTALLERS: Set<String> = setOf(
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.samsung.android.packageinstaller",
    )

    /**
     * True when the window is the system uninstall confirmation. Only the window's class name is
     * used (never its text), so we cannot tell *which* app is being removed: while the guard is on
     * the child cannot uninstall any app without the parent. This keeps the "we never read the
     * screen" promise in the accessibility disclosure.
     */
    fun isUninstallUi(pkg: String, className: String?): Boolean =
        pkg in PACKAGE_INSTALLERS && className != null && className.contains("Uninstall", ignoreCase = true)

    /**
     * Parent window: open only if it has not expired, is not longer than [MAX_PARENT_WINDOW_MS]
     * (a moved clock or tampered prefs cannot stretch it) and the phone has not rebooted since it
     * was opened (elapsed time restarts at boot). Uses elapsed time, not the wall clock.
     */
    fun isParentWindowOpen(nowElapsed: Long, untilElapsed: Long, bootCount: Int, windowBootCount: Int): Boolean =
        bootCount == windowBootCount && untilElapsed > nowElapsed && untilElapsed - nowElapsed <= MAX_PARENT_WINDOW_MS

    /**
     * Decides whether the protection layer covers [pkg]. Evaluated before the app lock, in every
     * lock mode and whether or not apps are currently locked.
     *
     * Never blocks: Zad X, the always-allowed safety core (phone, emergency, system UI, permission
     * dialogs) or anything while the parent window is open.
     */
    fun protectionGuard(
        pkg: String,
        className: String?,
        ownPackage: String,
        settingsLock: Boolean,
        uninstallGuard: Boolean,
        parentWindowOpen: Boolean,
        resolvedSettings: Set<String> = emptySet(),
    ): Guard {
        if (pkg.isEmpty() || pkg == ownPackage || parentWindowOpen) return Guard.NONE
        if (pkg in ALWAYS_ALLOWED && pkg !in SETTINGS_PACKAGES) return Guard.NONE
        if (settingsLock && (pkg in SETTINGS_PACKAGES || pkg in resolvedSettings)) return Guard.SETTINGS
        if (uninstallGuard && isUninstallUi(pkg, className)) return Guard.UNINSTALL
        return Guard.NONE
    }

    /**
     * Tamper reasons reported to the parent (mirrored by `protectionTamperReasons` in Dart).
     * A protection only counts as tampered if it was on before (we never alert for a step the
     * parent has not finished).
     */
    fun tamperReasons(
        serviceEverEnabled: Boolean,
        serviceEnabled: Boolean,
        uninstallGuard: Boolean,
        adminEverEnabled: Boolean,
        adminActive: Boolean,
    ): List<String> = buildList {
        if (serviceEverEnabled && !serviceEnabled) add("accessibility_off")
        if (uninstallGuard && adminEverEnabled && !adminActive) add("device_admin_off")
    }

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
        // The safety core and device roles are never locked, in any mode (even if a legacy game list
        // somehow contains e.g. the dialer).
        if (pkg in ALWAYS_ALLOWED || pkg in systemAllowed) return false
        if (mode != MODE_ALL_APPS) return pkg in selectedGames
        return pkg !in parentAllowed
    }

    // ---------------------------------------------------------------------------------------------
    // Free plan: the prayer lock ends by itself `prayerAutoEndMinutes` after it started
    // (plans-lock-integration). Measured with elapsed time since boot, which the child cannot change.
    // ---------------------------------------------------------------------------------------------

    /**
     * Milliseconds left in an auto-ending prayer lock.
     *
     * Same boot: `window - (nowElapsed - startElapsed)`. After a reboot elapsed time restarts, so we
     * fall back to the wall clock but never below [lastRemainingMs] (the remaining time last seen
     * before the reboot): moving the clock forward cannot shorten the lock, moving it back can only
     * lengthen it up to one window. Result is always within `0..windowMs`.
     */
    fun prayerRemainingMs(
        windowMs: Long,
        startElapsed: Long,
        anchorBoot: Int,
        startWallMs: Long,
        lastRemainingMs: Long,
        nowElapsed: Long,
        nowWallMs: Long,
        boot: Int,
    ): Long {
        if (windowMs <= 0) return Long.MAX_VALUE // paid plans: ends only when a parent approves
        if (boot == anchorBoot && nowElapsed >= startElapsed) {
            return (windowMs - (nowElapsed - startElapsed)).coerceIn(0, windowMs)
        }
        val byWall = (startWallMs + windowMs - nowWallMs).coerceIn(0, windowMs)
        return maxOf(byWall, lastRemainingMs.coerceIn(0, windowMs))
    }

    /** Elapsed-time start that leaves [remainingMs] of [windowMs] (used to re-anchor after a reboot). */
    fun reanchorStart(windowMs: Long, remainingMs: Long, nowElapsed: Long): Long =
        nowElapsed - (windowMs - remainingMs.coerceIn(0, windowMs))

    enum class PrayerAnchor { KEEP, ANCHOR, IGNORE }

    /**
     * What a policy with reason "prayer" from Flutter does to the native anchor.
     * [policySinceMs]: the lock start Flutter recorded (identifies the lock, never used for timing).
     */
    fun prayerAnchorAction(hasAnchor: Boolean, anchorSinceMs: Long?, policySinceMs: Long?, endedSinceMs: Long?): PrayerAnchor = when {
        policySinceMs != null && policySinceMs == endedSinceMs -> PrayerAnchor.IGNORE // already ended natively
        !hasAnchor -> PrayerAnchor.ANCHOR
        anchorSinceMs != null && policySinceMs != null && anchorSinceMs != policySinceMs -> PrayerAnchor.ANCHOR // a new prayer
        else -> PrayerAnchor.KEEP
    }

    /**
     * Whether controlled apps are blocked. A Flutter policy that is locked only *because of* prayer
     * stops blocking once the prayer lock auto-ended natively ([prayerOver]); other reasons still block.
     */
    fun shouldBlock(locked: Boolean, reason: String, prayerLock: Boolean, remainingMinutes: Int, prayerOver: Boolean): Boolean {
        val prayerActive = (prayerLock || reason == "prayer") && !prayerOver
        val lockedOther = locked && reason != "prayer"
        return lockedOther || prayerActive || remainingMinutes <= 0
    }

    // ---------------------------------------------------------------------------------------------
    // Google Play purchase sheet opened from Zad X (parent buying a plan).
    // ---------------------------------------------------------------------------------------------

    const val PLAY_STORE = "com.android.vending"

    /** How long after leaving Zad X the Play Store still counts as Zad X's purchase sheet. */
    const val PLAY_SHEET_WINDOW_MS = 2 * 60_000L

    /**
     * True when a Play Store window is part of a purchase started in Zad X: Play Store opened straight
     * from Zad X (or follows such an exempt Play window: payment dialogs), and less than
     * [PLAY_SHEET_WINDOW_MS] after Zad X was last in the foreground. After that the Play Store is an
     * ordinary app again (locked / metered), so reaching it once from Zad X does not exempt it for good.
     *
     * @param lastForeground last non-overlay foreground package (the service sets it to the Play Store
     *   after an exempt event, so the exemption is not inherited by later visits)
     * @param inExemptPlayChain the previous Play Store event was exempt
     * @param ownForegroundAtElapsed elapsed time when Zad X was last foreground (0 = never)
     */
    fun playSheetExempt(
        pkg: String,
        ownPackage: String,
        lastForeground: String?,
        inExemptPlayChain: Boolean,
        nowElapsed: Long,
        ownForegroundAtElapsed: Long,
    ): Boolean {
        if (pkg != PLAY_STORE || ownForegroundAtElapsed <= 0) return false
        val fromZadX = lastForeground == ownPackage || (lastForeground == PLAY_STORE && inExemptPlayChain)
        val age = nowElapsed - ownForegroundAtElapsed
        return fromZadX && age in 0..PLAY_SHEET_WINDOW_MS
    }
}
