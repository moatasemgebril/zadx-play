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

/** Quality Gate fix: the Play Store exemption is short-lived and not inherited. */
class PlaySheetExemptTest {
    private val own = "com.zadx.app"
    private val play = LockRules.PLAY_STORE
    private val t0 = 10_000_000L

    private fun exempt(last: String?, chain: Boolean, now: Long, ownAt: Long = t0) =
        LockRules.playSheetExempt(play, own, last, chain, now, ownAt)

    @Test
    fun playOpenedFromZadXIsExemptBriefly() {
        assertTrue(exempt(own, false, t0 + 5_000))
        // Follow-up Play windows of the same purchase (payment dialogs) within the window.
        assertTrue(exempt(play, true, t0 + 60_000))
    }

    @Test
    fun exemptionExpiresAfterTwoMinutes() {
        assertFalse(exempt(play, true, t0 + LockRules.PLAY_SHEET_WINDOW_MS + 1))
        assertFalse(exempt(own, false, t0 + LockRules.PLAY_SHEET_WINDOW_MS + 1))
    }

    @Test
    fun laterPlayVisitsAreNotExempt() {
        // Child left the purchase, opened another app, then came back to Play.
        assertFalse(exempt("com.some.game", false, t0 + 30_000))
        // Play reached again without an exempt chain (lastForeground is Play, chain broken).
        assertFalse(exempt(play, false, t0 + 30_000))
        // Zad X never seen in the foreground.
        assertFalse(exempt(own, false, t0, ownAt = 0))
        // Clock weirdness: Zad X time in the future.
        assertFalse(exempt(own, false, t0 - 1))
    }

    @Test
    fun onlyThePlayStoreIsEverExempt() {
        assertFalse(LockRules.playSheetExempt("com.roblox.client", own, own, true, t0 + 1, t0))
    }

    @Test
    fun safetyCoreBeatsTheLegacyGameList() {
        // Even if a legacy list contains the dialer or a device role, it is never locked.
        assertFalse(
            LockRules.isControlled("com.android.phone", own, LockRules.MODE_SELECTED_GAMES, setOf("com.android.phone"), emptySet(), emptySet()),
        )
        assertFalse(
            LockRules.isControlled("com.google.android.dialer", own, LockRules.MODE_SELECTED_GAMES,
                setOf("com.google.android.dialer"), emptySet(), setOf("com.google.android.dialer")),
        )
        assertTrue(
            LockRules.isControlled("com.roblox.client", own, LockRules.MODE_SELECTED_GAMES, setOf("com.roblox.client"), emptySet(), emptySet()),
        )
    }

    // ---- Zad X Kids schedules (mirror of test/schedule_test.dart) ----

    private val bedtime = LockRules.ScheduleWindow("bedtime", 21 * 60, 7 * 60, (1..7).toSet())
    private val study = LockRules.ScheduleWindow("study", 16 * 60, 18 * 60, setOf(7, 1, 2, 3, 4)) // Sun-Thu
    private val reading = LockRules.ScheduleWindow("reading", 17 * 60 + 30, 18 * 60 + 30, (1..7).toSet())

    @Test
    fun isoWeekdayFromCalendar() {
        assertEquals(7, LockRules.isoWeekday(1)) // Calendar.SUNDAY
        assertEquals(1, LockRules.isoWeekday(2)) // Calendar.MONDAY
        assertEquals(6, LockRules.isoWeekday(7)) // Calendar.SATURDAY
    }

    @Test
    fun bedtimeLocksAtNightAndOpensInTheMorning() {
        assertFalse(LockRules.scheduleActive(bedtime, 20 * 60 + 59, 1))
        assertTrue(LockRules.scheduleActive(bedtime, 21 * 60, 1))
        assertTrue(LockRules.scheduleActive(bedtime, 0, 2))
        assertTrue(LockRules.scheduleActive(bedtime, 6 * 60 + 59, 2))
        assertFalse(LockRules.scheduleActive(bedtime, 7 * 60, 2))
        val fridayOnly = bedtime.copy(days = setOf(5))
        assertTrue(LockRules.scheduleActive(fridayOnly, 6 * 60, 6)) // Saturday morning = Friday's night
        assertFalse(LockRules.scheduleActive(fridayOnly, 22 * 60, 6))
        assertFalse(LockRules.scheduleActive(fridayOnly, 6 * 60, 5))
    }

    @Test
    fun studyOnSchoolDaysOnlyAndPriority() {
        assertTrue(LockRules.scheduleActive(study, 16 * 60, 1))
        assertFalse(LockRules.scheduleActive(study, 18 * 60, 1))
        assertFalse(LockRules.scheduleActive(study, 16 * 60 + 30, 5)) // Friday
        assertEquals("study", LockRules.activeSchedule(listOf(reading, study, bedtime), 17 * 60 + 45, 1))
        assertEquals("reading", LockRules.activeSchedule(listOf(reading, study), 17 * 60 + 45, 5))
        assertEquals(null, LockRules.activeSchedule(listOf(reading, study, bedtime), 12 * 60, 1))
        assertFalse(LockRules.scheduleActive(study.copy(end = study.start), 16 * 60, 1))
        assertFalse(LockRules.scheduleActive(bedtime.copy(kind = "prayer"), 22 * 60, 1))
    }

    @Test
    fun schedulesSurviveStorage() {
        val all = listOf(bedtime, study, reading)
        assertEquals(all, LockRules.decodeSchedules(LockRules.encodeSchedules(all)))
        assertEquals(emptyList<LockRules.ScheduleWindow>(), LockRules.decodeSchedules(null))
        assertEquals(emptyList<LockRules.ScheduleWindow>(), LockRules.decodeSchedules("prayer,1,2,1;bedtime,x,2,1;study,1,9999,1"))
    }
}

/** Zad X Kids: moving the phone's clock or time zone cannot end bedtime. */
class ClockTamperTest {
    private val min = 60_000L
    private val bedtime = LockRules.ScheduleWindow("bedtime", 21 * 60, 7 * 60, (1..7).toSet())
    private val cairo = java.util.TimeZone.getTimeZone("Africa/Cairo")
    private val tokyo = java.util.TimeZone.getTimeZone("Asia/Tokyo")
    private val losAngeles = java.util.TimeZone.getTimeZone("America/Los_Angeles")

    /** 2026-11-23 (Monday) 22:00 in Cairo (UTC+2) = 20:00 UTC. */
    private val night = 1_795_464_000_000L

    private fun clock(
        nowWall: Long,
        nowElapsed: Long,
        anchorTrusted: Long? = night,
        anchorElapsed: Long = 1_000_000L,
        boot: Int = 3,
        anchorBoot: Int = 3,
        lastOffset: Long = 0,
        autoTime: Boolean = false,
    ) = LockRules.trustedClock(nowWall, nowElapsed, boot, anchorTrusted, anchorElapsed, anchorBoot, lastOffset, autoTime)

    @Test
    fun scheduleIsReadInTheParentsTimeZone() {
        assertEquals("bedtime", LockRules.activeScheduleAt(listOf(bedtime), night, cairo))
        assertEquals(null, LockRules.activeScheduleAt(listOf(bedtime), night + 14 * 60 * min, cairo)) // noon
        // The same instant is 12:00 in Los Angeles: switching the phone there does not open bedtime.
        val trusted = LockRules.ClockState(night, tampered = false)
        assertEquals("bedtime", LockRules.activeScheduleChecked(listOf(bedtime), trusted, cairo, night, losAngeles))
        assertEquals(null, LockRules.activeScheduleAt(listOf(bedtime), night, losAngeles))
        assertEquals("bedtime", LockRules.activeScheduleAt(listOf(bedtime), night, tokyo)) // 05:00 there
    }

    @Test
    fun honestClockIsTrusted() {
        val c = clock(night + 5 * min, 1_000_000L + 5 * min)
        assertFalse(c.tampered)
        assertEquals(night + 5 * min, c.trustedWallMs)
        assertFalse(clock(night + 5 * min + 30_000, 1_000_000L + 5 * min).tampered) // drift
        assertFalse(clock(night, 0L, anchorTrusted = null).tampered) // first check ever
    }

    @Test
    fun clockMovedForwardByHandKeepsBedtime() {
        // 5 minutes after 22:00 the child sets the clock to 09:00 the next morning.
        val wall = night + 11 * 60 * min
        val c = clock(wall, 1_000_000L + 5 * min)
        assertTrue(c.tampered)
        assertEquals(night + 5 * min, c.trustedWallMs)
        assertEquals("bedtime", LockRules.activeScheduleChecked(listOf(bedtime), c, cairo, wall, cairo))
        // The offset survives a reboot (elapsed time restarts at boot).
        val after = clock(wall + 2 * min, 5_000L, anchorTrusted = c.trustedWallMs, boot = 4, lastOffset = c.offsetFrom(wall))
        assertTrue(after.tampered)
        assertEquals(night + 7 * min, after.trustedWallMs)
    }

    @Test
    fun smallStepsAddUp() {
        // Two steps of 90 s: each alone is under the tolerance, together they are not.
        val first = clock(night + 90_000, 1_000_000L)
        assertFalse(first.tampered)
        val second = clock(night + 180_000, 1_000_000L, anchorTrusted = first.trustedWallMs)
        assertTrue(second.tampered)
        assertEquals(night, second.trustedWallMs)
    }

    @Test
    fun networkTimeIsTrusted() {
        val c = clock(night + 11 * 60 * min, 1_000_000L + 5 * min, autoTime = true)
        assertFalse(c.tampered)
        assertEquals(night + 11 * 60 * min, c.trustedWallMs)
    }

    @Test
    fun movingTheClockIntoBedtimeOnlyLocks() {
        val noon = night + 14 * 60 * min
        // Trusted time says noon (open), the phone shows 22:00: tampered, so the lock stays on.
        val c = LockRules.ClockState(noon, tampered = true)
        assertEquals("bedtime", LockRules.activeScheduleChecked(listOf(bedtime), c, cairo, night, cairo))
        assertEquals(null, LockRules.activeScheduleChecked(listOf(bedtime), c.copy(tampered = false), cairo, night, cairo))
    }

    @Test
    fun zoneIdsAreValidated() {
        assertEquals("Africa/Cairo", LockRules.zoneOrNull("Africa/Cairo")?.id)
        assertEquals(null, LockRules.zoneOrNull("Mars/Olympus"))
        assertEquals(null, LockRules.zoneOrNull(null))
    }

    @Test
    fun clockChangeIsATamperReason() {
        assertEquals(listOf("clock_changed"), LockRules.tamperReasons(false, false, false, false, false, clockChanged = true))
        assertEquals(emptyList<String>(), LockRules.tamperReasons(false, false, false, false, false))
    }
}
