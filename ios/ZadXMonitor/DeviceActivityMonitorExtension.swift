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

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if activity.rawValue == "zadx.playBudget" {
            SharedStore.timeUp = true
            SharedStore.reason = "noTime"
            SharedStore.shieldGames()
        }
    }
}
