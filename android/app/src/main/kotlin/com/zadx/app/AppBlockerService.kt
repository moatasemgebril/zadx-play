package com.zadx.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
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
 * Google Play: apps using the Accessibility API for parental control must
 * complete the Permissions Declaration Form and show a prominent disclosure
 * before sending the user to Accessibility settings (see docs/STORE_CHECKLIST.md).
 */
class AppBlockerService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var foregroundGame: String? = null
    private var lastForeground: String? = null

    private companion object {
        const val PLAY_STORE = "com.android.vending"
    }

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

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) {
            // The shield itself must not open the Play Store exemption below.
            lastForeground = if (event.className?.toString() == BlockActivity::class.java.name) null else pkg
            return
        }
        // Google Play's purchase sheet opened from Zad X (parent buying a plan) is part of Zad X's flow.
        if (pkg == PLAY_STORE && lastForeground == packageName) return
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
        stopTicking()
        AppLockChannel.emit(mapOf("type" to "blocked_attempt", "package" to pkg))
        // Send the game to the background first so it cannot keep running beside the shield
        // (split-screen / pop-up window), then show the shield.
        performGlobalAction(GLOBAL_ACTION_HOME)
        startActivity(
            Intent(this, BlockActivity::class.java)
                .putExtra(BlockActivity.EXTRA_REASON, LockStore.reason(this))
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
