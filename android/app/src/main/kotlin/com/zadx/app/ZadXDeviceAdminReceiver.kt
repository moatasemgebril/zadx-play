package com.zadx.app

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

/**
 * Optional uninstall protection (docs/decisions/DEVICE-PROTECTION.md).
 *
 * Declares **no** device policies (res/xml/zadx_device_admin.xml has an empty `<uses-policies>`):
 * Zad X cannot wipe, lock, reset passwords or read anything. Being an *active* device admin only
 * means Android refuses to uninstall Zad X until the admin is turned off. The parent turns it on and
 * off inside Zad X with the PIN; turning it off from Settings is possible (Android always allows it)
 * but Settings is locked for the child, and the parent is alerted (tamper report).
 *
 * Google Play: Device Admin for parental controls must be disclosed (docs/STORE_CHECKLIST.md).
 */
class ZadXDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        LockStore.markAdminEnabled(context, true)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        LockStore.markAdminEnabled(context, false)
    }

    /** Shown by Android before the admin is turned off from Settings. */
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence {
        val arabic = context.resources.configuration.locales[0].language == "ar"
        return if (arabic) {
            "لو قفلت دي، الطفل هيقدر يمسح Zad X. هيوصل تنبيه لولي الأمر."
        } else {
            "If you turn this off, Zad X can be deleted. The parent will be alerted."
        }
    }

    companion object {
        fun component(ctx: Context) = ComponentName(ctx, ZadXDeviceAdminReceiver::class.java)

        fun isActive(ctx: Context): Boolean =
            (ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager).isAdminActive(component(ctx))

        /** Opens Android's own activation screen. Call after the parent PIN + disclosure. */
        fun requestActivation(ctx: Context, explanation: String) {
            ctx.startActivity(
                Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                    .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, component(ctx))
                    .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, explanation)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }

        /** Parent turned it off in Zad X (after the PIN): not a tamper event. */
        fun deactivate(ctx: Context) {
            LockStore.forgetAdmin(ctx)
            if (isActive(ctx)) {
                (ctx.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager).removeActiveAdmin(component(ctx))
            }
        }
    }
}
