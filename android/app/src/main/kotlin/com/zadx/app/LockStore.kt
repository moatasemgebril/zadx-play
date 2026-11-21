package com.zadx.app

import android.content.Context
import android.content.SharedPreferences

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
    ) {
        prefs(ctx).edit()
            .putBoolean("locked", locked)
            .putString("reason", reason)
            .putStringSet("packages", packages.toSet())
            .putInt("remaining", remainingMinutes)
            .putString("mode", mode)
            .putStringSet("allowed", allowedPackages.toSet())
            .putBoolean("allowMessaging", allowMessaging)
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
        return p.getBoolean("locked", true) || p.getBoolean("prayerLock", false) || p.getInt("remaining", 0) <= 0
    }

    fun reason(ctx: Context): String {
        val p = prefs(ctx)
        return if (p.getBoolean("prayerLock", false)) "prayer" else p.getString("reason", "requiredTasks")!!
    }

    /** Set by PrayerLockReceiver at adhan time; cleared when Flutter sends a new policy. */
    fun setPrayerLock(ctx: Context, on: Boolean) {
        prefs(ctx).edit().putBoolean("prayerLock", on).apply()
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
}
