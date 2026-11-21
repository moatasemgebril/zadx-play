import DeviceActivity
import FamilyControls
import Flutter
import ManagedSettings
import SwiftUI
import UIKit

/// Flutter ⇄ iOS bridge for game locking (Screen Time API).
/// Mirrors lib/services/app_lock/app_lock_service.dart.
///
/// Requires the Family Controls entitlement (request the *Distribution* variant
/// from Apple before App Store submission) and the App Group `group.com.zadx.app`.
final class AppLockPlugin: NSObject, FlutterStreamHandler {
    static let shared = AppLockPlugin()

    private var sink: FlutterEventSink?
    private let center = DeviceActivityCenter()

    static func register(with messenger: FlutterBinaryMessenger) {
        let methods = FlutterMethodChannel(name: "com.zadx.app/app_lock", binaryMessenger: messenger)
        let events = FlutterEventChannel(name: "com.zadx.app/app_lock_events", binaryMessenger: messenger)
        events.setStreamHandler(shared)
        methods.setMethodCallHandler { call, result in shared.handle(call, result: result) }

        NotificationCenter.default.addObserver(
            shared, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    // MARK: - Method calls

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "hasPermissions":
            result(AuthorizationCenter.shared.authorizationStatus == .approved)

        case "requestPermissions":
            Task { @MainActor in
                do {
                    // .child: the parent approves on their device via Family Sharing.
                    try await AuthorizationCenter.shared.requestAuthorization(for: .child)
                    result(true)
                } catch {
                    do {
                        // Single-device families (parent sets up the child's phone directly).
                        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                        result(true)
                    } catch {
                        result(false)
                    }
                }
            }

        case "pickGames":
            presentPicker(allowed: false, result: result)

        case "pickAllowedApps":
            presentPicker(allowed: true, result: result)

        case "applyPolicy":
            let locked = args["locked"] as? Bool ?? true
            let reason = args["reason"] as? String ?? "none"
            let remaining = args["remainingMinutes"] as? Int ?? 0
            SharedStore.reason = reason
            SharedStore.prayerLock = reason == "prayer"
            SharedStore.mode = args["mode"] as? String ?? "selectedGames"
            SharedStore.prayerAutoEndMinutes = args["prayerAutoEndMinutes"] as? Int ?? 0
            SharedStore.lastRemainingMinutes = remaining
            if locked {
                SharedStore.shieldGames()
                center.stopMonitoring([.playBudget])
            } else {
                SharedStore.timeUp = false
                SharedStore.unshieldGames()
                startBudget(minutes: remaining)
            }
            result(nil)

        // MARK: Device protection (docs/decisions/DEVICE-PROTECTION.md)
        case "setProtection":
            if AuthorizationCenter.shared.authorizationStatus == .approved {
                SharedStore.applyProtection(
                    lockSettings: args["settingsLock"] as? Bool ?? true,
                    preventRemoval: args["uninstallGuard"] as? Bool ?? false
                )
            }
            result(nil)

        case "protectionStatus":
            let approved = AuthorizationCenter.shared.authorizationStatus == .approved
            if approved { SharedStore.authorizationEverApproved = true }
            let ever = SharedStore.authorizationEverApproved
            result([
                "platform": "ios",
                "authorization": approved,
                "authorizationEverApproved": ever,
                "tamper": (ever && !approved) ? ["screen_time_off"] : [String](),
            ])

        // Android-only (Settings window / Device Admin): iOS cannot lock the Settings app.
        case "openParentWindow", "parentWindowSeconds":
            result(0)
        case "closeParentWindow", "requestDeviceAdmin", "removeDeviceAdmin":
            result(nil)
        case "deviceAdminActive", "openDeviceSettings":
            result(false)

        case "schedulePrayerLocks":
            let times = (args["times"] as? [NSNumber] ?? []).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            schedulePrayerLocks(times)
            result(nil)

        case "launchGame":
            if let scheme = args["iosUrlScheme"] as? String, let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                result(true)
            } else {
                result(false) // the child opens the game from the Home Screen
            }


        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Picker

    /// `allowed == false`: games/apps that use play time (legacy lock list + time budget).
    /// `allowed == true`: apps the parent always allows in "allApps" mode.
    private func presentPicker(allowed: Bool, result: @escaping FlutterResult) {
        let model = PickerModel(selection: allowed ? SharedStore.allowedSelection : SharedStore.selection)
        let host = UIHostingController(rootView: GamesPickerView(model: model) { saved in
            if let saved {
                if allowed { SharedStore.allowedSelection = saved } else { SharedStore.selection = saved }
                // Re-apply an active shield so the new choice takes effect at once.
                if SharedStore.store.shield.applicationCategories != nil || SharedStore.store.shield.applications != nil {
                    SharedStore.shieldGames()
                }
            }
            UIApplication.shared.topViewController?.dismiss(animated: true)
            result(nil)
        })
        UIApplication.shared.topViewController?.present(host, animated: true)
    }

    // MARK: - Device activity

    /// Unshield now; the monitor extension re-shields after `minutes` of use of the selected games.
    /// In "allApps" mode DeviceActivityEvent cannot express "every app", so the budget still counts the
    /// parent's "apps that use play time" selection (recommend Games + Social + Entertainment).
    private func startBudget(minutes: Int) {
        guard minutes > 0 else { SharedStore.shieldGames(); return }
        let s = SharedStore.selection
        let event = DeviceActivityEvent(
            applications: s.applicationTokens,
            categories: s.categoryTokens,
            threshold: DateComponents(minute: minutes)
        )
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: false
        )
        center.stopMonitoring([.playBudget])
        try? center.startMonitoring(.playBudget, during: schedule, events: [.budgetReached: event])
    }

    /// One 15-minute activity per prayer; intervalDidStart in the extension shields the games.
    private func schedulePrayerLocks(_ times: [Date]) {
        let names = (0..<10).map { DeviceActivityName("zadx.prayer.\($0)") }
        center.stopMonitoring(names)
        let cal = Calendar.current
        for (i, start) in times.prefix(names.count).enumerated() {
            // Free plan: the interval is the auto-end window; its end lifts the prayer shield (ZadXMonitor).
            let minutes = SharedStore.prayerIntervalMinutes(autoEnd: SharedStore.prayerAutoEndMinutes)
            let end = start.addingTimeInterval(TimeInterval(minutes * 60))
            let schedule = DeviceActivitySchedule(
                intervalStart: cal.dateComponents([.year, .month, .day, .hour, .minute], from: start),
                intervalEnd: cal.dateComponents([.year, .month, .day, .hour, .minute], from: end),
                repeats: false
            )
            try? center.startMonitoring(names[i], during: schedule)
        }
    }

    // MARK: - Events to Flutter

    @objc private func appDidBecomeActive() {
        if SharedStore.prayerLock { sink?(["type": "prayer_lock"]) }
        if SharedStore.timeUp { sink?(["type": "time_up"]) }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        appDidBecomeActive()
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }
}

extension DeviceActivityName {
    static let playBudget = Self("zadx.playBudget")
}

extension DeviceActivityEvent.Name {
    static let budgetReached = Self("zadx.budgetReached")
}

// MARK: - SwiftUI picker

final class PickerModel: ObservableObject {
    @Published var selection: FamilyActivitySelection
    init(selection: FamilyActivitySelection) { self.selection = selection }
}

struct GamesPickerView: View {
    @ObservedObject var model: PickerModel
    let onDone: (FamilyActivitySelection?) -> Void

    var body: some View {
        NavigationView {
            FamilyActivityPicker(selection: $model.selection)
                .navigationTitle("Zad X")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("✕") { onDone(nil) } }
                    ToolbarItem(placement: .confirmationAction) { Button("OK") { onDone(model.selection) } }
                }
        }
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        var top = connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
