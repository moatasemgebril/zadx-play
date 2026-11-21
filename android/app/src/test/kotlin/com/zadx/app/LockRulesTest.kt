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

/** Free plan: the prayer lock ends by itself, on a clock the child cannot change. */
class PrayerAutoEndTest {
    private val window = 20 * 60_000L
    private val min = 60_000L

    private fun remaining(nowElapsed: Long, nowWall: Long, boot: Int = 1, lastRemaining: Long = 0) =
        LockRules.prayerRemainingMs(
            windowMs = window, startElapsed = 1_000_000L, anchorBoot = 1, startWallMs = 5_000_000_000L,
            lastRemainingMs = lastRemaining, nowElapsed = nowElapsed, nowWallMs = nowWall, boot = boot,
        )

    @Test
    fun endsAfterTheWindowOnElapsedTime() {
        assertEquals(window - 5 * min, remaining(1_000_000L + 5 * min, 5_000_000_000L + 5 * min))
        assertEquals(0L, remaining(1_000_000L + 21 * min, 5_000_000_000L))
    }

    @Test
    fun movingTheWallClockDoesNotChangeItOnTheSameBoot() {
        // Child moves the clock 3 hours forward after 2 minutes: 18 minutes still left.
        assertEquals(window - 2 * min, remaining(1_000_000L + 2 * min, 5_000_000_000L + 180 * min))
    }

    @Test
    fun afterRebootFallsBackToWallClockButNeverShortens() {
        // Rebooted with 15 minutes left, then the clock moved 3 hours forward: still 15 minutes.
        assertEquals(15 * min, remaining(10_000L, 5_000_000_000L + 180 * min, boot = 2, lastRemaining = 15 * min))
        // Honest clock after reboot: wall time says 12 minutes left (more than the last seen 10).
        assertEquals(12 * min, remaining(10_000L, 5_000_000_000L + 8 * min, boot = 2, lastRemaining = 10 * min))
        // Clock moved back a day: capped at one window.
        assertEquals(window, remaining(10_000L, 5_000_000_000L - 24 * 60 * min, boot = 2, lastRemaining = 10 * min))
        val start = LockRules.reanchorStart(window, 15 * min, 10_000L)
        assertEquals(15 * min, window - (10_000L - start))
    }

    @Test
    fun paidPlansNeverAutoEnd() {
        assertEquals(
            Long.MAX_VALUE,
            LockRules.prayerRemainingMs(0, 0, 1, 0, 0, Long.MAX_VALUE / 2, Long.MAX_VALUE / 2, 1),
        )
    }

    @Test
    fun anchorActions() {
        assertEquals(LockRules.PrayerAnchor.ANCHOR, LockRules.prayerAnchorAction(false, null, 100L, null))
        assertEquals(LockRules.PrayerAnchor.KEEP, LockRules.prayerAnchorAction(true, null, 100L, null))
        assertEquals(LockRules.PrayerAnchor.KEEP, LockRules.prayerAnchorAction(true, 100L, 100L, null))
        assertEquals(LockRules.PrayerAnchor.ANCHOR, LockRules.prayerAnchorAction(true, 100L, 900L, null))
        assertEquals(LockRules.PrayerAnchor.IGNORE, LockRules.prayerAnchorAction(false, null, 100L, 100L))
    }

    @Test
    fun blockingAfterAutoEnd() {
        // Locked only for prayer and it auto-ended: open (minutes left).
        assertFalse(LockRules.shouldBlock(true, "prayer", true, 30, prayerOver = true))
        assertTrue(LockRules.shouldBlock(true, "prayer", true, 30, prayerOver = false))
        // Auto-ended but no minutes left: still blocked.
        assertTrue(LockRules.shouldBlock(true, "prayer", false, 0, prayerOver = true))
        // Other reasons are unaffected.
        assertTrue(LockRules.shouldBlock(true, "requiredTasks", false, 30, prayerOver = true))
        assertFalse(LockRules.shouldBlock(false, "none", false, 30, prayerOver = false))
        // Native alarm fired while Flutter said unlocked.
        assertTrue(LockRules.shouldBlock(false, "none", true, 30, prayerOver = false))
    }
}
