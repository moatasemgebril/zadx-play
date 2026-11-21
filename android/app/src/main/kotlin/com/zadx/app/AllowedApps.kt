package com.zadx.app

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.provider.Telephony
import android.telecom.TelecomManager
import android.view.inputmethod.InputMethodManager

/**
 * Resolves, on the device only, the packages that fill safety roles and so must never be locked:
 * dialer, launcher, keyboard, settings, other accessibility services and (if the parent allows)
 * SMS + contacts. Nothing here leaves the device.
 *
 * Package visibility (Android 11+) comes from the intent `<queries>` in AndroidManifest.additions.xml;
 * we do not use QUERY_ALL_PACKAGES.
 */
object AllowedApps {
    private const val CACHE_MS = 60_000L
    private var cache: Set<String>? = null
    private var cacheKey: Boolean? = null
    private var cachedAt = 0L

    /** Cached for a minute: the default launcher/keyboard can change in Settings. */
    @Synchronized
    fun systemAllowed(ctx: Context, allowMessaging: Boolean): Set<String> {
        val now = SystemClock.elapsedRealtime()
        val c = cache
        if (c != null && cacheKey == allowMessaging && now - cachedAt < CACHE_MS) return c
        val fresh = compute(ctx, allowMessaging)
        cache = fresh
        cacheKey = allowMessaging
        cachedAt = now
        return fresh
    }

    @Synchronized
    fun invalidate() {
        cache = null
        settingsCache = null
    }

    private var settingsCache: Set<String>? = null

    /**
     * Packages that answer `Settings.ACTION_SETTINGS` on this device (vendor builds may rename the
     * Settings app). Locked for the child by the protection layer; see [LockRules.protectionGuard].
     */
    @Synchronized
    fun settingsPackages(ctx: Context): Set<String> {
        settingsCache?.let { return it }
        val pm = ctx.packageManager
        val out = mutableSetOf<String>()
        runCatching {
            val intent = Intent(Settings.ACTION_SETTINGS)
            pm.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName?.let(out::add)
            pm.queryIntentActivities(intent, 0)
                .filter { isSystem(it.activityInfo.applicationInfo) }
                .forEach { out.add(it.activityInfo.packageName) }
        }
        // Safety: a resolver must never make the phone, launcher or Zad X itself a "settings" app.
        out.remove(ctx.packageName)
        out.removeAll(LockRules.ALWAYS_ALLOWED - LockRules.SETTINGS_PACKAGES)
        runCatching {
            // Blocking the home app would send the shield into a HOME loop.
            val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
            pm.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName?.let(out::remove)
        }
        settingsCache = out
        return out
    }

    private fun compute(ctx: Context, allowMessaging: Boolean): Set<String> {
        val pm = ctx.packageManager
        val out = mutableSetOf<String>()

        // Phone / dialer (never configurable).
        runCatching {
            val telecom = ctx.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
            telecom.defaultDialerPackage?.let(out::add)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) telecom.systemDialerPackage?.let(out::add)
        }

        // Launcher(s): the default home app + system home apps. A third-party launcher is trusted only
        // while it is the default (blocking it would send the shield into a HOME loop).
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        runCatching {
            pm.resolveActivity(home, PackageManager.MATCH_DEFAULT_ONLY)?.activityInfo?.packageName?.let(out::add)
            pm.queryIntentActivities(home, 0)
                .filter { isSystem(it.activityInfo.applicationInfo) }
                .forEach { out.add(it.activityInfo.packageName) }
        }

        // Keyboard: the default IME + enabled system IMEs ("game keyboards" stay locked).
        runCatching {
            Settings.Secure.getString(ctx.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD)
                ?.substringBefore('/')?.takeIf { it.isNotEmpty() }?.let(out::add)
            val imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            imm.enabledInputMethodList
                .filter { isSystem(it.serviceInfo.applicationInfo) }
                .forEach { out.add(it.packageName) }
        }

        // Settings app (vendor builds may rename it).
        runCatching {
            pm.resolveActivity(Intent(Settings.ACTION_SETTINGS), PackageManager.MATCH_DEFAULT_ONLY)
                ?.activityInfo?.packageName?.let(out::add)
        }

        // Other enabled accessibility services (TalkBack, Switch Access…) must keep working.
        runCatching {
            Settings.Secure.getString(ctx.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                ?.split(':')
                ?.mapNotNull { it.substringBefore('/').takeIf(String::isNotBlank) }
                ?.forEach(out::add)
        }

        // SMS + contacts with parents (parent-configurable, default on).
        if (allowMessaging) {
            runCatching { Telephony.Sms.getDefaultSmsPackage(ctx)?.let(out::add) }
            for (category in listOf(Intent.CATEGORY_APP_MESSAGING, Intent.CATEGORY_APP_CONTACTS)) {
                runCatching {
                    pm.queryIntentActivities(Intent(Intent.ACTION_MAIN).addCategory(category), 0)
                        .forEach { out.add(it.activityInfo.packageName) }
                }
            }
        }

        out.remove(ctx.packageName) // handled separately; keeps lists tidy for the parent UI
        return out
    }

    private fun isSystem(info: ApplicationInfo?): Boolean =
        info != null && (info.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0

    /** Launchable apps the parent may add to the allow-list (label + package), sorted by label. */
    fun launchableApps(ctx: Context): List<Map<String, String>> {
        val pm = ctx.packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return pm.queryIntentActivities(launcher, 0)
            .map { it.activityInfo.packageName to it.loadLabel(pm).toString() }
            .filter { it.first != ctx.packageName }
            .distinctBy { it.first }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }

    /** Always-allowed packages that are installed, with labels, for the parent's read-only list. */
    fun alwaysAllowedApps(ctx: Context, allowMessaging: Boolean): List<Map<String, String>> {
        val pm = ctx.packageManager
        return (LockRules.ALWAYS_ALLOWED + systemAllowed(ctx, allowMessaging))
            .mapNotNull { pkg ->
                runCatching { pkg to pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString() }.getOrNull()
            }
            .filter { it.first != "android" }
            .sortedBy { it.second.lowercase() }
            .map { mapOf("package" to it.first, "label" to it.second) }
    }
}
