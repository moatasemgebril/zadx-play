package com.zadx.app

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Flutter ⇄ Android bridge for game locking. Mirrors lib/services/app_lock/app_lock_service.dart. */
object AppLockChannel {
    private const val METHODS = "com.zadx.app/app_lock"
    private const val EVENTS = "com.zadx.app/app_lock_events"

    private var sink: EventChannel.EventSink? = null
    private val main = Handler(Looper.getMainLooper())

    fun emit(event: Map<String, Any?>) {
        main.post { sink?.success(event) }
    }

    fun register(engine: FlutterEngine, context: Context) {
        EventChannel(engine.dartExecutor.binaryMessenger, EVENTS).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                sink = events
                // Report minutes played while Flutter was closed.
                val offline = LockStore.drainPendingMinutes(context)
                repeat(offline) { emit(mapOf("type" to "session_minute")) }
                // A prayer alarm may have fired while Flutter was closed.
                if (LockStore.isPrayerLocked(context)) emit(mapOf("type" to "prayer_lock"))
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })

        MethodChannel(engine.dartExecutor.binaryMessenger, METHODS).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermissions" -> result.success(isAccessibilityEnabled(context))

                "requestPermissions" -> {
                    // The Flutter UI must show a prominent disclosure before calling this.
                    context.startActivity(
                        Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(isAccessibilityEnabled(context))
                }

                "pickGames", "pickAllowedApps" -> result.success(null) // iOS only

                // Parent allow-list editor (runs behind the parent PIN; the list never leaves the device).
                "listApps" -> result.success(AllowedApps.launchableApps(context))

                "alwaysAllowedApps" -> result.success(
                    AllowedApps.alwaysAllowedApps(context, call.argument<Boolean>("allowMessaging") ?: true),
                )

                "applyPolicy" -> {
                    @Suppress("UNCHECKED_CAST")
                    val packages = call.argument<List<String>>("androidPackages") ?: emptyList()
                    val reason = call.argument<String>("reason") ?: "none"
                    LockStore.save(
                        context,
                        locked = call.argument<Boolean>("locked") ?: true,
                        reason = reason,
                        packages = packages,
                        remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0,
                        mode = call.argument<String>("mode") ?: LockRules.MODE_SELECTED_GAMES,
                        allowedPackages = call.argument<List<String>>("allowedPackages") ?: emptyList(),
                        allowMessaging = call.argument<Boolean>("allowMessaging") ?: true,
                    )
                    // Flutter is the source of truth for the prayer lock once it is running.
                    LockStore.setPrayerLock(context, reason == "prayer")
                    result.success(null)
                }

                "schedulePrayerLocks" -> {
                    val times = call.argument<List<Number>>("times")?.map { it.toLong() } ?: emptyList()
                    PrayerLockReceiver.schedule(context, times)
                    result.success(null)
                }

                "launchGame" -> {
                    val pkg = call.argument<String>("androidPackage")
                    val intent = pkg?.let { context.packageManager.getLaunchIntentForPackage(it) }
                    if (intent != null) {
                        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } else {
                        openStore(context, pkg)
                        result.success(false)
                    }
                }

                "openCompanionApp" -> {
                    // PlayStation Family / Microsoft Family Safety: open the app or its store page.
                    val pkg = call.argument<String>("androidPackage")
                    val intent = pkg?.let { context.packageManager.getLaunchIntentForPackage(it) }
                    if (intent != null) {
                        context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    } else {
                        openStore(context, pkg)
                    }
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun openStore(context: Context, pkg: String?) {
        if (pkg == null) return
        try {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: ActivityNotFoundException) {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=$pkg"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
    }

    private fun isAccessibilityEnabled(context: Context): Boolean {
        val expected = ComponentName(context, AppBlockerService::class.java).flattenToString()
        val enabled = Settings.Secure.getString(context.contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
            ?: return false
        val splitter = TextUtils.SimpleStringSplitter(':').apply { setString(enabled) }
        return splitter.any { it.equals(expected, ignoreCase = true) }
    }
}
