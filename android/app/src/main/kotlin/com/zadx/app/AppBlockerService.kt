package com.zadx.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * Watches which app is in the foreground. When a controlled app opens while
 * play is not allowed, it shows [BlockActivity] on top. While play is allowed
 * it counts minutes of real play and reports them to Flutter.
 *
 * "Controlled" depends on the mode (see [LockRules]): in allApps mode every app except the
 * always-allowed core (phone, emergency, launcher, keyboard, settings, Zad X…) and the parent's
 * allow-list; in selectedGames mode only the chosen games. Only the package name of the
 * foreground window is read; window content is never accessed.
 *
 * Device protection (docs/decisions/DEVICE-PROTECTION.md): independent of the lock state, the
 * Settings app is covered for the child (unless the parent opened a short window with the PIN) and,
 * when "Prevent deleting Zad X" is on, so is the system uninstall dialog. Phone and emergency are
 * never covered. Decided by [LockRules.protectionGuard] from the package + class name only.
 *
 * Google Play: apps using the Accessibility API for parental control must
 * complete the Permissions Declaration Form and show a prominent disclosure
 * before sending the user to Accessibility settings (see docs/STORE_CHECKLIST.md).
 */
class AppBlockerService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var foregroundGame: String? = null
    private var lastForeground: String? = null

    /** Elapsed time when Zad X (not its shield) was last in the foreground; see [LockRules.playSheetExempt]. */
    private var ownForegroundAt = 0L
    private var inExemptPlayChain = false

    private val minuteTicker = object : Runnable {
        override fun run() {
            val pkg = foregroundGame ?: return
            LockStore.consumeMinute(this@AppBlockerService)
            AppLockChannel.emit(mapOf("type" to "session_minute", "package" to pkg))
            if (LockStore.shouldBlock(this@AppBlockerService)) {
                block(pkg)
            } else {
                handler.postDelayed(this, 60_000)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        // Remember that protection was on, so turning the service off later is reported as tamper.
        LockStore.markServiceEnabled(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) {
            // The shield itself must not open the Play Store exemption below.
            val shieldShown = event.className?.toString() == BlockActivity::class.java.name
            lastForeground = if (shieldShown) null else pkg
            if (!shieldShown) ownForegroundAt = SystemClock.elapsedRealtime()
            inExemptPlayChain = false
            return
        }
        // Settings for the parent only / uninstall guard: applies whether or not apps are locked.
        when (LockStore.protectionGuard(this, pkg, event.className?.toString())) {
            LockRules.Guard.SETTINGS -> return shield(pkg, "settings")
            LockRules.Guard.UNINSTALL -> return shield(pkg, "uninstall")
            LockRules.Guard.NONE -> Unit
        }
        // Google Play's purchase sheet opened from Zad X (parent buying a plan) is part of Zad X's flow.
        // Exempt only for ~2 minutes after leaving Zad X, and not inherited by later Play Store visits.
        if (LockRules.playSheetExempt(pkg, packageName, lastForeground, inExemptPlayChain, SystemClock.elapsedRealtime(), ownForegroundAt)) {
            lastForeground = LockRules.PLAY_STORE
            inExemptPlayChain = true
            stopTicking()
            return
        }
        if (!isTransientOverlay(pkg)) inExemptPlayChain = false
        // The notification shade, volume dialog or keyboard opening over a game must not stop
        // the minute counter (otherwise pulling down the shade gave unmetered play time).
        if (isTransientOverlay(pkg)) return

        lastForeground = pkg
        if (!LockStore.isControlled(this, pkg)) {
            stopTicking()
            return
        }
        if (LockStore.shouldBlock(this)) {
            block(pkg)
        } else if (foregroundGame != pkg) {
            stopTicking()
            foregroundGame = pkg
            AppLockChannel.emit(mapOf("type" to "session_started", "package" to pkg))
            handler.postDelayed(minuteTicker, 60_000)
        }
    }

    private fun isTransientOverlay(pkg: String): Boolean {
        if (pkg == "com.android.systemui") return true
        val ime = Settings.Secure.getString(contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD) ?: return false
        return ime.substringBefore('/') == pkg
    }

    private fun block(pkg: String) {
        AppLockChannel.emit(mapOf("type" to "blocked_attempt", "package" to pkg))
        shield(pkg, LockStore.reason(this))
    }

    /** Sends [pkg] to the background and shows the shield with [reason]. */
    private fun shield(pkg: String, reason: String) {
        stopTicking()
        lastForeground = pkg
        // Send the app to the background first so it cannot keep running beside the shield
        // (split-screen / pop-up window), then show the shield.
        performGlobalAction(GLOBAL_ACTION_HOME)
        startActivity(
            Intent(this, BlockActivity::class.java)
                .putExtra(BlockActivity.EXTRA_REASON, reason)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        )
    }

    private fun stopTicking() {
        handler.removeCallbacks(minuteTicker)
        foregroundGame = null
    }

    override fun onInterrupt() = stopTicking()

    override fun onDestroy() {
        stopTicking()
        super.onDestroy()
    }
}
