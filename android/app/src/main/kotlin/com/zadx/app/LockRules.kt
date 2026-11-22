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
        clockChanged: Boolean = false,
    ): List<String> = buildList {
        if (serviceEverEnabled && !serviceEnabled) add("accessibility_off")
        if (uninstallGuard && adminEverEnabled && !adminActive) add("device_admin_off")
        // Zad X Kids: the time / time zone was moved by hand while schedules are on (see [trustedClock]).
        if (clockChanged) add("clock_changed")
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

    // ---------------------------------------------------------------------------------------------
    // Zad X Kids schedules (docs/decisions/ZADX-KIDS-VARIANT.md). Mirrors `ScheduledLock.activeAt` /
    // `activeScheduledLock` in lib/features/schedule/scheduled_lock.dart: keep both in sync.
    // ---------------------------------------------------------------------------------------------

    /** Schedule kinds by priority (the first active one is the lock reason). */
    val SCHEDULE_KINDS: List<String> = listOf("bedtime", "study", "reading")

    /**
     * One lock window in local time. [start]/[end] = minutes after midnight; `end < start` crosses
     * midnight. [days] = ISO weekdays (1 = Monday … 7 = Sunday) on which the window STARTS.
     */
    data class ScheduleWindow(val kind: String, val start: Int, val end: Int, val days: Set<Int>)

    /** ISO weekday (1 = Monday … 7 = Sunday) from `Calendar.DAY_OF_WEEK` (1 = Sunday … 7 = Saturday). */
    fun isoWeekday(calendarDayOfWeek: Int): Int = ((calendarDayOfWeek + 5) % 7) + 1

    fun scheduleActive(w: ScheduleWindow, minuteOfDay: Int, isoWeekday: Int): Boolean {
        if (w.kind !in SCHEDULE_KINDS || w.start == w.end || w.days.isEmpty()) return false
        val yesterday = if (isoWeekday == 1) 7 else isoWeekday - 1
        return if (w.end > w.start) {
            isoWeekday in w.days && minuteOfDay >= w.start && minuteOfDay < w.end
        } else {
            (isoWeekday in w.days && minuteOfDay >= w.start) || (yesterday in w.days && minuteOfDay < w.end)
        }
    }

    /** The kind of the schedule locking the device now (bedtime > study > reading), or null. */
    fun activeSchedule(windows: List<ScheduleWindow>, minuteOfDay: Int, isoWeekday: Int): String? =
        windows.filter { scheduleActive(it, minuteOfDay, isoWeekday) }
            .minByOrNull { SCHEDULE_KINDS.indexOf(it.kind) }
            ?.kind

    /**
     * The schedule locking the device at the instant [epochMs], read in [zone] (the time zone the
     * parent saved the schedules in, not the phone's current one: changing the phone's time zone
     * cannot move bedtime).
     */
    fun activeScheduleAt(windows: List<ScheduleWindow>, epochMs: Long, zone: java.util.TimeZone): String? {
        if (windows.isEmpty()) return null
        val cal = java.util.Calendar.getInstance(zone).apply { timeInMillis = epochMs }
        val minute = cal.get(java.util.Calendar.HOUR_OF_DAY) * 60 + cal.get(java.util.Calendar.MINUTE)
        return activeSchedule(windows, minute, isoWeekday(cal.get(java.util.Calendar.DAY_OF_WEEK)))
    }

    /**
     * Schedule lock decision with the clock checks: the schedule active at the [trusted] instant in the
     * parent's [parentZone]. While the clock looks tampered, a schedule active by the phone's own wall
     * clock / zone also keeps the lock on (moving the clock can never open a lock, only keep one).
     */
    fun activeScheduleChecked(
        windows: List<ScheduleWindow>,
        trusted: ClockState,
        parentZone: java.util.TimeZone,
        deviceWallMs: Long,
        deviceZone: java.util.TimeZone,
    ): String? {
        activeScheduleAt(windows, trusted.trustedWallMs, parentZone)?.let { return it }
        return if (trusted.tampered) activeScheduleAt(windows, deviceWallMs, deviceZone) else null
    }

    /** A valid IANA id, or null (`TimeZone.getTimeZone` silently returns GMT for unknown ids). */
    fun zoneOrNull(id: String?): java.util.TimeZone? {
        if (id.isNullOrBlank()) return null
        val tz = java.util.TimeZone.getTimeZone(id)
        return if (tz.id == id) tz else null
    }

    // ---------------------------------------------------------------------------------------------
    // Clock tamper (Zad X Kids schedules): a child must not escape bedtime by moving the phone's clock.
    // Between two checks on the same boot, real time advances exactly like elapsed time since boot
    // (SystemClock.elapsedRealtime, which the child cannot change). A wall clock that jumped away from
    // that, while automatic (network) time is off, was set by hand: we keep using the trusted time and
    // tell the parent.
    // ---------------------------------------------------------------------------------------------

    /** Wall-clock difference we still accept as drift / a network correction. */
    const val CLOCK_TOLERANCE_MS = 2 * 60_000L

    /** [trustedWallMs]: our best estimate of real time. [tampered]: the phone's clock is off by hand. */
    data class ClockState(val trustedWallMs: Long, val tampered: Boolean) {
        fun offsetFrom(nowWallMs: Long): Long = trustedWallMs - nowWallMs
    }

    /**
     * @param anchorTrustedMs trusted time at the last check (null = never checked)
     * @param anchorElapsed / [anchorBoot] elapsed time and boot count at that check
     * @param lastOffsetMs trusted − wall at the last check (used after a reboot, when elapsed restarts)
     * @param autoTime Settings.Global.AUTO_TIME: the phone takes its time from the network, the child
     *   cannot set it by hand, so the wall clock is trusted again
     */
    fun trustedClock(
        nowWallMs: Long,
        nowElapsed: Long,
        boot: Int,
        anchorTrustedMs: Long?,
        anchorElapsed: Long,
        anchorBoot: Int,
        lastOffsetMs: Long,
        autoTime: Boolean,
    ): ClockState {
        if (autoTime) return ClockState(nowWallMs, false)
        if (anchorTrustedMs != null && boot == anchorBoot && nowElapsed >= anchorElapsed) {
            val expected = anchorTrustedMs + (nowElapsed - anchorElapsed)
            // Always the elapsed-based time, so several small steps add up instead of each being "drift".
            return ClockState(expected, kotlin.math.abs(expected - nowWallMs) > CLOCK_TOLERANCE_MS)
        }
        // Rebooted (elapsed restarted) or first check: keep the last known offset.
        return ClockState(nowWallMs + lastOffsetMs, kotlin.math.abs(lastOffsetMs) > CLOCK_TOLERANCE_MS)
    }

    /** Compact storage form: "kind,start,end,1.2.3;kind,…". */
    fun encodeSchedules(windows: List<ScheduleWindow>): String =
        windows.joinToString(";") { "${it.kind},${it.start},${it.end},${it.days.sorted().joinToString(".")}" }

    /** Inverse of [encodeSchedules]; malformed entries are dropped. */
    fun decodeSchedules(encoded: String?): List<ScheduleWindow> =
        (encoded ?: "").split(";").mapNotNull { entry ->
            val parts = entry.split(",")
            if (parts.size != 4) return@mapNotNull null
            val start = parts[1].toIntOrNull() ?: return@mapNotNull null
            val end = parts[2].toIntOrNull() ?: return@mapNotNull null
            if (parts[0] !in SCHEDULE_KINDS || start !in 0 until 24 * 60 || end !in 0 until 24 * 60) return@mapNotNull null
            val days = parts[3].split(".").mapNotNull { it.toIntOrNull() }.filter { it in 1..7 }.toSet()
            ScheduleWindow(parts[0], start, end, days)
        }
}
