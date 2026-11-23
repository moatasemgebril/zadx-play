package com.zadx.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Zad X Kids schedules: the phone's time (ACTION_TIME_CHANGED) or time zone (ACTION_TIMEZONE_CHANGED)
 * was changed. Both broadcasts are exempt from Android 8's implicit-broadcast limits, so this works
 * while Zad X is closed.
 *
 * The schedules never follow the new clock: [LockStore.activeSchedule] reads them at the trusted time
 * (elapsed time since the last check) in the time zone the parent saved them in, so bedtime stays on.
 * Here we only re-check the clock right away and, when the change was made by hand, tell Flutter so it
 * reports the tamper reason `clock_changed` to the parent (also reported on the next start/resume).
 */
class ClockChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val zone = intent.action == Intent.ACTION_TIMEZONE_CHANGED
        if (intent.action != Intent.ACTION_TIME_CHANGED && !zone) return
        if (LockStore.onClockChanged(context, timeZoneChanged = zone)) {
            AppLockChannel.emit(mapOf("type" to "clock_changed"))
        }
    }
}
