package com.zadx.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** Locks controlled games at each adhan even if Zad X is not running. */
class PrayerLockReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        LockStore.setPrayerLock(context, true)
        AppLockChannel.emit(mapOf("type" to "prayer_lock"))
    }

    companion object {
        fun schedule(context: Context, timesMillis: List<Long>) {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            timesMillis.forEachIndexed { i, at ->
                val pi = PendingIntent.getBroadcast(
                    context,
                    1000 + i,
                    Intent(context, PrayerLockReceiver::class.java),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                } else {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                }
            }
        }
    }
}
