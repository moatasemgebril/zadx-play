package com.zadx.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent

/**
 * Watches which app is in the foreground. When a controlled game opens while
 * play is not allowed, it shows [BlockActivity] on top. While play is allowed
 * it counts minutes of real play and reports them to Flutter.
 *
 * Google Play: apps using the Accessibility API for parental control must
 * complete the Permissions Declaration Form and show a prominent disclosure
 * before sending the user to Accessibility settings (see docs/STORE_CHECKLIST.md).
 */
class AppBlockerService : AccessibilityService() {

    private val handler = Handler(Looper.getMainLooper())
    private var foregroundGame: String? = null

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
        if (pkg == packageName) return

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

    private fun block(pkg: String) {
        stopTicking()
        AppLockChannel.emit(mapOf("type" to "blocked_attempt", "package" to pkg))
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
