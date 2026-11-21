package com.zadx.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure rule tests (no Android runtime). Run: ./gradlew :app:testDebugUnitTest (CI does this). */
class LockRulesTest {
    private val own = "com.zadx.app"

    private fun guard(
        pkg: String,
        className: String? = null,
        settingsLock: Boolean = true,
        uninstallGuard: Boolean = true,
        window: Boolean = false,
        resolved: Set<String> = emptySet(),
    ) = LockRules.protectionGuard(pkg, className, own, settingsLock, uninstallGuard, window, resolved)

    @Test
    fun settingsAppIsLockedForTheChildAtAllTimes() {
        assertEquals(LockRules.Guard.SETTINGS, guard("com.android.settings"))
        assertEquals(LockRules.Guard.SETTINGS, guard("com.google.android.settings.intelligence"))
        // Vendor Settings resolved from ACTION_SETTINGS on the device.
        assertEquals(LockRules.Guard.SETTINGS, guard("com.vendor.settings", resolved = setOf("com.vendor.settings")))
    }

    @Test
    fun parentWindowOpensSettingsAndUninstall() {
        assertEquals(LockRules.Guard.NONE, guard("com.android.settings", window = true))
        assertEquals(
            LockRules.Guard.NONE,
            guard("com.google.android.packageinstaller", "com.android.packageinstaller.UninstallerActivity", window = true),
        )
    }

    @Test
    fun parentCanTurnSettingsLockOff() {
        assertEquals(LockRules.Guard.NONE, guard("com.android.settings", settingsLock = false))
    }

    @Test
    fun emergencyPhoneAndSystemUiAreNeverCovered() {
        val safety = listOf(
            "com.android.phone", "com.android.server.telecom", "com.android.incallui", "com.android.emergency",
            "com.google.android.apps.safetyhub", "com.android.cellbroadcastreceiver", "com.android.systemui",
            "com.google.android.permissioncontroller", "android", "com.sec.android.app.safetyassurance",
        )
        for (pkg in safety) {
            // Even if a broken resolver reported them as "settings".
            assertEquals(pkg, LockRules.Guard.NONE, guard(pkg, resolved = setOf(pkg)))
        }
    }

    @Test
    fun zadXItselfIsNeverCovered() {
        assertEquals(LockRules.Guard.NONE, guard(own, resolved = setOf(own)))
    }

    @Test
    fun uninstallDialogIsCoveredOnlyWhenTheGuardIsOn() {
        val cls = "com.android.packageinstaller.UninstallerActivity"
        assertEquals(LockRules.Guard.UNINSTALL, guard("com.google.android.packageinstaller", cls))
        assertEquals(LockRules.Guard.UNINSTALL, guard("com.android.packageinstaller", cls, settingsLock = false))
        assertEquals(LockRules.Guard.NONE, guard("com.google.android.packageinstaller", cls, uninstallGuard = false))
        // Installing / permission screens of the installer are not the uninstall dialog.
        assertEquals(
            LockRules.Guard.NONE,
            guard("com.google.android.packageinstaller", "com.android.packageinstaller.PackageInstallerActivity"),
        )
        assertFalse(LockRules.isUninstallUi("com.some.game", "UninstallFakeActivity"))
    }

    @Test
    fun ordinaryAppsAreLeftToTheAppLock() {
        assertEquals(LockRules.Guard.NONE, guard("com.roblox.client"))
    }

    @Test
    fun parentWindowExpiresAndCannotBeStretched() {
        val now = 1_000_000L
        assertTrue(LockRules.isParentWindowOpen(now, now + 5 * 60_000, 7, 7))
        assertFalse(LockRules.isParentWindowOpen(now, now - 1, 7, 7)) // expired
        assertFalse(LockRules.isParentWindowOpen(now, now + 60 * 60_000, 7, 7)) // longer than the max
        assertFalse(LockRules.isParentWindowOpen(now, now + 60_000, 8, 7)) // rebooted since
        assertFalse(LockRules.isParentWindowOpen(now, 0, 7, 7)) // never opened
    }

    @Test
    fun tamperIsReportedOnlyForProtectionThatWasOn() {
        assertEquals(listOf("accessibility_off"), LockRules.tamperReasons(true, false, false, false, false))
        assertEquals(emptyList<String>(), LockRules.tamperReasons(false, false, false, false, false))
        assertEquals(listOf("device_admin_off"), LockRules.tamperReasons(true, true, true, true, false))
        assertEquals(emptyList<String>(), LockRules.tamperReasons(true, true, false, true, false))
    }

    @Test
    fun allAppsLockStillWorks() {
        assertTrue(LockRules.isControlled("com.some.game", own, LockRules.MODE_ALL_APPS, emptySet(), emptySet(), emptySet()))
        assertFalse(LockRules.isControlled("com.android.settings", own, LockRules.MODE_ALL_APPS, emptySet(), emptySet(), emptySet()))
    }
}
