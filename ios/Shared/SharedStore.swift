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
    private static let allowedKey = "zadx.allowedSelection"
    private static let modeKey = "zadx.lockMode"

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

    /// Apps / websites the parent always allows in "allApps" mode (opaque tokens, never uploaded).
    static var allowedSelection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: allowedKey),
                  let value = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return value
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: allowedKey)
        }
    }

    /// "allApps" (shield everything except allowedSelection) or "selectedGames" (legacy: shield selection).
    /// See docs/decisions/DEVICE-WIDE-LOCK.md.
    static var mode: String {
        get { defaults.string(forKey: modeKey) ?? "selectedGames" }
        set { defaults.set(newValue, forKey: modeKey) }
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
        if mode == "allApps" {
            // Everything except the parent's allowed apps/sites. Phone and emergency SOS are never
            // shielded by Screen Time. Zad X should be in the allowed selection (the parent UI says so).
            let allowed = allowedSelection
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: allowed.applicationTokens)
            store.shield.webDomainCategories = .all(except: allowed.webDomainTokens)
            return
        }
        let s = selection
        store.shield.applications = s.applicationTokens.isEmpty ? nil : s.applicationTokens
        store.shield.applicationCategories = s.categoryTokens.isEmpty ? nil : .specific(s.categoryTokens)
        store.shield.webDomainCategories = nil
    }

    static func unshieldGames() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
    }

    // MARK: - Device protection (docs/decisions/DEVICE-PROTECTION.md)
    //
    // What iOS allows (Screen Time API, needs FamilyControls authorization):
    //  * `application.denyAppRemoval`  – no app can be deleted while on (iOS has no per-app variant).
    //  * `account.lockAccounts`        – no adding/removing accounts (Apple ID, mail).
    //  * `passcode.lockPasscode`       – the device passcode cannot be changed or removed.
    //  * `dateAndTime.requireAutomaticDateAndTime` – the clock cannot be moved to skip a lock.
    // What iOS does NOT allow: locking or shielding the Settings app itself, or stopping the child from
    // revoking Screen Time access when Zad X was authorized with `.individual`. With `.child`
    // (Family Sharing) removing the authorization needs the parent's Apple ID / Screen Time passcode.
    // A separate named store keeps these settings when the app shield is cleared.

    // MARK: - Free plan prayer auto-end (plans-lock-integration)

    /// Free plan: the prayer lock ends by itself this many minutes after the adhan (0 = paid plans:
    /// only a parent's approval ends it). The prayer DeviceActivity interval is scheduled this long,
    /// and `intervalDidEnd` in ZadXMonitor lifts the prayer shield. iOS runs these schedules itself;
    /// with device protection on, `requireAutomaticDateAndTime` stops the child moving the clock.
    static var prayerAutoEndMinutes: Int {
        get { defaults.integer(forKey: "zadx.prayerAutoEnd") }
        set { defaults.set(max(0, min(newValue, 24 * 60)), forKey: "zadx.prayerAutoEnd") }
    }

    /// Minutes left the last time Zad X sent a policy (used to restart the budget after an auto-end).
    static var lastRemainingMinutes: Int {
        get { defaults.integer(forKey: "zadx.lastRemaining") }
        set { defaults.set(max(0, newValue), forKey: "zadx.lastRemaining") }
    }

    /// Pure rule (mirrors Kotlin `LockRules.shouldBlock` for the prayer part): after a Free prayer lock
    /// ends, apps stay shielded only if no minutes are left.
    static func shieldAfterPrayerEnds(timeUp: Bool, remainingMinutes: Int) -> Bool {
        timeUp || remainingMinutes <= 0
    }

    /// Prayer activity length: Apple's minimum is 15 minutes.
    static func prayerIntervalMinutes(autoEnd: Int) -> Int { autoEnd > 0 ? max(15, autoEnd) : 15 }

    static let protectionStore = ManagedSettingsStore(named: .init("zadx.protection"))
    private static let authEverKey = "zadx.authEverApproved"

    static func applyProtection(lockSettings: Bool, preventRemoval: Bool) {
        protectionStore.application.denyAppRemoval = preventRemoval ? true : nil
        protectionStore.account.lockAccounts = lockSettings ? true : nil
        protectionStore.passcode.lockPasscode = lockSettings ? true : nil
        protectionStore.dateAndTime.requireAutomaticDateAndTime = lockSettings ? true : nil
    }

    /// Set once Screen Time access was approved, so a later revocation is reported to the parent.
    static var authorizationEverApproved: Bool {
        get { defaults.bool(forKey: authEverKey) }
        set { defaults.set(newValue, forKey: authEverKey) }
    }
}
