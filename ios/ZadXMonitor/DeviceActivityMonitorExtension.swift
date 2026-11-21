import DeviceActivity
import Foundation
import ManagedSettings

/// Device Activity Monitor extension (target "ZadXMonitor").
/// Runs even when Zad X is closed:
/// * prayer activities → shield games at the adhan
/// * play budget threshold → shield games when earned minutes run out
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity.rawValue.hasPrefix("zadx.prayer.") {
            SharedStore.prayerLock = true
            SharedStore.reason = "prayer"
            SharedStore.shieldGames()
        }
    }

    /// Free plan: the prayer lock ends on its own when the prayer interval (= auto-end window) ends.
    /// Paid plans (auto-end 0) keep the shield until a parent approves "I prayed" in Zad X.
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.rawValue.hasPrefix("zadx.prayer."),
              SharedStore.prayerAutoEndMinutes > 0,
              SharedStore.prayerLock else { return }
        SharedStore.prayerLock = false
        let remaining = SharedStore.lastRemainingMinutes
        if SharedStore.shieldAfterPrayerEnds(timeUp: SharedStore.timeUp, remainingMinutes: remaining) {
            SharedStore.reason = "noTime"
            SharedStore.shieldGames()
            return
        }
        SharedStore.reason = "none"
        SharedStore.unshieldGames()
        // Keep metering the daily limit while Zad X is closed.
        let s = SharedStore.selection
        let budget = DeviceActivityName("zadx.playBudget")
        let center = DeviceActivityCenter()
        center.stopMonitoring([budget])
        try? center.startMonitoring(
            budget,
            during: DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: false
            ),
            events: [
                DeviceActivityEvent.Name("zadx.budgetReached"): DeviceActivityEvent(
                    applications: s.applicationTokens,
                    categories: s.categoryTokens,
                    threshold: DateComponents(minute: remaining)
                ),
            ]
        )
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if activity.rawValue == "zadx.playBudget" {
            SharedStore.timeUp = true
            SharedStore.reason = "noTime"
            SharedStore.shieldGames()
        }
    }
}
