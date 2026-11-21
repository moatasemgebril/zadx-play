package com.zadx.app

import android.content.Context
import android.content.SharedPreferences
import android.os.SystemClock
import android.provider.Settings

/**
 * Lock policy shared between Flutter (via AppLockChannel), the AccessibilityService
 * and alarm receivers. Persisted so blocking keeps working when Zad X is closed.
 */
object LockStore {
    private const val PREFS = "zadx_lock"

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun save(
        ctx: Context,
        locked: Boolean,
        reason: String,
        packages: List<String>,
        remainingMinutes: Int,
        mode: String = LockRules.MODE_SELECTED_GAMES,
        allowedPackages: List<String> = emptyList(),
        allowMessaging: Boolean = true,
        prayerAutoEndMinutes: Int = 0,
    ) {
        prefs(ctx).edit()
            .putBoolean("locked", locked)
            .putString("reason", reason)
            .putStringSet("packages", packages.toSet())
            .putInt("remaining", remainingMinutes)
            .putString("mode", mode)
            .putStringSet("allowed", allowedPackages.toSet())
            .putBoolean("allowMessaging", allowMessaging)
            .putInt("prayerAutoEnd", prayerAutoEndMinutes.coerceIn(0, 24 * 60))
            .apply()
        AllowedApps.invalidate()
    }

    /** "allApps" (lock everything except allowed) or "selectedGames" (legacy). */
    fun mode(ctx: Context): String =
        prefs(ctx).getString("mode", LockRules.MODE_SELECTED_GAMES) ?: LockRules.MODE_SELECTED_GAMES

    fun allowMessaging(ctx: Context): Boolean = prefs(ctx).getBoolean("allowMessaging", true)

    /** True when [pkg] is subject to the lock and the play-minute counter. See [LockRules]. */
    fun isControlled(ctx: Context, pkg: String): Boolean {
        val p = prefs(ctx)
        val mode = mode(ctx)
        return LockRules.isControlled(
            pkg = pkg,
            ownPackage = ctx.packageName,
            mode = mode,
            selectedGames = p.getStringSet("packages", emptySet())!!,
            parentAllowed = p.getStringSet("allowed", emptySet())!!,
            // Only resolve system roles when needed (allApps mode).
            systemAllowed = if (mode == LockRules.MODE_ALL_APPS) AllowedApps.systemAllowed(ctx, allowMessaging(ctx)) else emptySet(),
        )
    }

    fun controlledPackages(ctx: Context): Set<String> =
        prefs(ctx).getStringSet("packages", emptySet())!!

    /** True when a controlled app must be blocked right now. */
    fun shouldBlock(ctx: Context): Boolean {
        val p = prefs(ctx)
        return LockRules.shouldBlock(
            locked = p.getBoolean("locked", true),
            reason = p.getString("reason", "requiredTasks")!!,
            prayerLock = p.getBoolean("prayerLock", false),
            remainingMinutes = p.getInt("remaining", 0),
            prayerOver = prayerOver(ctx),
        )
    }

    fun reason(ctx: Context): String {
        val p = prefs(ctx)
        val stored = p.getString("reason", "requiredTasks")!!
        val prayerActive = (p.getBoolean("prayerLock", false) || stored == "prayer") && !prayerOver(ctx)
        return when {
            prayerActive -> "prayer"
            stored == "prayer" -> "noTime" // prayer auto-ended; still blocked only because no minutes are left
            else -> stored
        }
    }

    /**
     * Prayer lock on/off. [fresh] = a new adhan (PrayerLockReceiver): always re-anchor the auto-end
     * timer. From Flutter ([sinceMs] = the lock start it recorded) see [LockRules.prayerAnchorAction].
     */
    fun setPrayerLock(ctx: Context, on: Boolean, fresh: Boolean = false, sinceMs: Long? = null) {
        val p = prefs(ctx)
        val e = p.edit()
        if (!on) {
            e.putBoolean("prayerLock", false).remove("pStartElapsed").remove("pBoot").remove("pStartWall")
                .remove("pLastRemaining").remove("pSince")
            e.apply()
            return
        }
        val action = if (fresh) LockRules.PrayerAnchor.ANCHOR else LockRules.prayerAnchorAction(
            hasAnchor = p.contains("pStartElapsed"),
            anchorSinceMs = if (p.contains("pSince")) p.getLong("pSince", 0) else null,
            policySinceMs = sinceMs,
            endedSinceMs = if (p.contains("pEndedSince")) p.getLong("pEndedSince", 0) else null,
        )
        when (action) {
            LockRules.PrayerAnchor.IGNORE -> return // this lock already ended on its own
            LockRules.PrayerAnchor.ANCHOR -> {
                e.putLong("pStartElapsed", SystemClock.elapsedRealtime())
                    .putInt("pBoot", bootCount(ctx))
                    .putLong("pStartWall", System.currentTimeMillis())
                    .remove("pLastRemaining")
                    .remove("pEnded")
                if (sinceMs != null) e.putLong("pSince", sinceMs) else e.remove("pSince")
            }
            LockRules.PrayerAnchor.KEEP -> if (sinceMs != null && !p.contains("pSince")) e.putLong("pSince", sinceMs)
        }
        e.putBoolean("prayerLock", true).apply()
    }

    /**
     * Free plan: true once the prayer lock has run for `prayerAutoEnd` minutes (elapsed time; see
     * [LockRules.prayerRemainingMs]). Clears the native prayer lock when it ends.
     */
    @Synchronized
    fun prayerOver(ctx: Context): Boolean {
        val p = prefs(ctx)
        val windowMs = p.getInt("prayerAutoEnd", 0) * 60_000L
        if (windowMs <= 0) return false
        // Ended on its own earlier; a late Flutter policy for the same lock must not re-block.
        if (!p.contains("pStartElapsed")) return p.getBoolean("pEnded", false)
        val nowElapsed = SystemClock.elapsedRealtime()
        val boot = bootCount(ctx)
        val remaining = LockRules.prayerRemainingMs(
            windowMs = windowMs,
            startElapsed = p.getLong("pStartElapsed", nowElapsed),
            anchorBoot = p.getInt("pBoot", boot),
            startWallMs = p.getLong("pStartWall", System.currentTimeMillis()),
            lastRemainingMs = p.getLong("pLastRemaining", 0L),
            nowElapsed = nowElapsed,
            nowWallMs = System.currentTimeMillis(),
            boot = boot,
        )
        if (remaining <= 0) {
            val since = if (p.contains("pSince")) p.getLong("pSince", 0) else null
            setPrayerLock(ctx, false)
            val done = p.edit().putBoolean("pEnded", true)
            if (since != null) done.putLong("pEndedSince", since)
            done.apply()
            return true
        }
        val e = p.edit()
        if (p.getInt("pBoot", boot) != boot) {
            // Rebooted: continue on the new boot's elapsed clock from what is left.
            e.putLong("pStartElapsed", LockRules.reanchorStart(windowMs, remaining, nowElapsed)).putInt("pBoot", boot)
        }
        if (kotlin.math.abs(p.getLong("pLastRemaining", -1L) - remaining) >= 30_000L) e.putLong("pLastRemaining", remaining)
        e.apply()
        return false
    }

    fun isPrayerLocked(ctx: Context): Boolean = prefs(ctx).getBoolean("prayerLock", false)

    /** Called every minute a controlled game is in the foreground. */
    fun consumeMinute(ctx: Context) {
        val p = prefs(ctx)
        val remaining = (p.getInt("remaining", 0) - 1).coerceAtLeast(0)
        p.edit()
            .putInt("remaining", remaining)
            .putInt("pendingMinutes", p.getInt("pendingMinutes", 0) + 1)
            .apply()
    }

    /** Minutes played while Flutter was not listening; Flutter drains them on resume. */
    fun drainPendingMinutes(ctx: Context): Int {
        val p = prefs(ctx)
        val m = p.getInt("pendingMinutes", 0)
        p.edit().putInt("pendingMinutes", 0).apply()
        return m
    }

    // ---------------------------------------------------------------------------------------------
    // Device protection (docs/decisions/DEVICE-PROTECTION.md). Defaults: Settings locked for the
    // child (owner decision), uninstall guard off until the parent turns it on.
    // ---------------------------------------------------------------------------------------------

    fun setProtection(ctx: Context, settingsLock: Boolean, uninstallGuard: Boolean) {
        prefs(ctx).edit()
            .putBoolean("settingsLock", settingsLock)
            .putBoolean("uninstallGuard", uninstallGuard)
            .apply()
    }

    fun settingsLock(ctx: Context): Boolean = prefs(ctx).getBoolean("settingsLock", true)

    fun uninstallGuard(ctx: Context): Boolean = prefs(ctx).getBoolean("uninstallGuard", false)

    private fun bootCount(ctx: Context): Int =
        runCatching { Settings.Global.getInt(ctx.contentResolver, Settings.Global.BOOT_COUNT) }.getOrDefault(-1)

    /** Opens the parent window (Settings + uninstall allowed). Call only after the parent PIN. */
    fun openParentWindow(ctx: Context, minutes: Int) {
        val ms = (minutes.coerceIn(1, 10) * 60_000L).coerceAtMost(LockRules.MAX_PARENT_WINDOW_MS)
        prefs(ctx).edit()
            .putLong("windowUntil", SystemClock.elapsedRealtime() + ms)
            .putInt("windowBoot", bootCount(ctx))
            .apply()
    }

    fun closeParentWindow(ctx: Context) {
        prefs(ctx).edit().remove("windowUntil").remove("windowBoot").apply()
    }

    fun isParentWindowOpen(ctx: Context): Boolean {
        val p = prefs(ctx)
        return LockRules.isParentWindowOpen(
            nowElapsed = SystemClock.elapsedRealtime(),
            untilElapsed = p.getLong("windowUntil", 0L),
            bootCount = bootCount(ctx),
            windowBootCount = p.getInt("windowBoot", Int.MIN_VALUE),
        )
    }

    /** Seconds left in the parent window (0 when closed). */
    fun parentWindowSecondsLeft(ctx: Context): Int {
        if (!isParentWindowOpen(ctx)) return 0
        val left = prefs(ctx).getLong("windowUntil", 0L) - SystemClock.elapsedRealtime()
        return (left / 1000).toInt().coerceAtLeast(0)
    }

    fun protectionGuard(ctx: Context, pkg: String, className: String?): LockRules.Guard {
        val settingsLock = settingsLock(ctx)
        val uninstallGuard = uninstallGuard(ctx)
        if (!settingsLock && !uninstallGuard) return LockRules.Guard.NONE
        return LockRules.protectionGuard(
            pkg = pkg,
            className = className,
            ownPackage = ctx.packageName,
            settingsLock = settingsLock,
            uninstallGuard = uninstallGuard,
            parentWindowOpen = isParentWindowOpen(ctx),
            resolvedSettings = if (settingsLock) AllowedApps.settingsPackages(ctx) else emptySet(),
        )
    }

    // Tamper detection: remember that a protection was on, so turning it off can be reported.
    fun markServiceEnabled(ctx: Context) = prefs(ctx).edit().putBoolean("serviceEverEnabled", true).apply()

    fun serviceEverEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean("serviceEverEnabled", false)

    fun markAdminEnabled(ctx: Context, on: Boolean) {
        val e = prefs(ctx).edit()
        if (on) e.putBoolean("adminEverEnabled", true) else e.putLong("adminDisabledAt", System.currentTimeMillis())
        e.apply()
    }

    fun adminEverEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean("adminEverEnabled", false)

    /** The parent removed Device Admin from Zad X with the PIN: not a tamper event. */
    fun forgetAdmin(ctx: Context) = prefs(ctx).edit().remove("adminEverEnabled").apply()
}
