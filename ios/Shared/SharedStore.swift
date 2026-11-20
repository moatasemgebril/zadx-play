import FamilyControls
import Foundation
import ManagedSettings

/// State shared by the app and its extensions through the App Group container.
/// Add this file to the Runner, ZadXMonitor and ZadXShield targets.
enum SharedStore {
    static let appGroup = "group.com.zadx.app"
    static let defaults = UserDefaults(suiteName: appGroup)!

    private static let selectionKey = "zadx.selection"
    private static let prayerLockKey = "zadx.prayerLock"
    private static let timeUpKey = "zadx.timeUp"
    private static let reasonKey = "zadx.reason"

    /// Games the parent picked in FamilyActivityPicker (opaque tokens).
    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: selectionKey),
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return value
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: selectionKey)
        }
    }

    static var prayerLock: Bool {
        get { defaults.bool(forKey: prayerLockKey) }
        set { defaults.set(newValue, forKey: prayerLockKey) }
    }

    static var timeUp: Bool {
        get { defaults.bool(forKey: timeUpKey) }
        set { defaults.set(newValue, forKey: timeUpKey) }
    }

    /// Why games are locked: prayer | requiredTasks | noTime | none
    static var reason: String {
        get { defaults.string(forKey: reasonKey) ?? "requiredTasks" }
        set { defaults.set(newValue, forKey: reasonKey) }
    }

    static let store = ManagedSettingsStore(named: .init("zadx"))

    static func shieldGames() {
        let s = selection
        store.shield.applications = s.applicationTokens.isEmpty ? nil : s.applicationTokens
        store.shield.applicationCategories = s.categoryTokens.isEmpty ? nil : .specific(s.categoryTokens)
    }

    static func unshieldGames() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
    }
}
