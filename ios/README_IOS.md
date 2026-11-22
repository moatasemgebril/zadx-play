# iOS setup (Screen Time API)

Zad X locks games on iPhone/iPad with Apple's **FamilyControls**, **ManagedSettings**
and **DeviceActivity** frameworks (iOS 16+).

## 1. Apple approval (start this first — it can take weeks)
1. Apple Developer account (Organization recommended).
2. Request the **Family Controls (Distribution)** entitlement:
   https://developer.apple.com/contact/request/family-controls-distribution
   Development builds work with the development entitlement; App Store builds need the distribution one.

## 2. Xcode targets
After `flutter create` (see main README), open `ios/Runner.xcworkspace`:

| Target | Type | Files |
|---|---|---|
| Runner | (existing) | `Runner/AppLockPlugin.swift`, `Runner/AppDelegate.swift`, `Shared/SharedStore.swift` |
| ZadXMonitor | Device Activity Monitor Extension | `ZadXMonitor/DeviceActivityMonitorExtension.swift`, `Shared/SharedStore.swift` |
| ZadXShield | Shield Configuration Extension | `ZadXShield/ShieldConfigurationExtension.swift`, `Shared/SharedStore.swift` |

For **all three** targets:
- Deployment target: iOS 16.0
- Signing & Capabilities → **Family Controls** and **App Groups** → `group.com.zadx.app`
- Use `Runner/Runner.entitlements` as a template for the extensions' entitlements.

Set `CFBundleDisplayName` = `Zad X Play` in `Runner/Info.plist`, and add:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>roblox</string>
  <string>minecraft</string>
</array>
<key>UIBackgroundModes</key>
<array><string>audio</string></array>
```

## 3. Sounds
- `adhan_short.caf` (< 30 s, notification sound) → add to the Runner target.
- Full adhan MP3s → `assets/audio/` (see `lib/data/catalog/quran.dart`).

## 4. How it works
- **Child device** asks for authorization (`.child`; the parent approves through Family Sharing,
  or `.individual` when the parent sets up the child's phone directly).
- Parent picks games with Apple's **FamilyActivityPicker** (iOS never reveals app ids).
- `applyPolicy` shields/unshields the selected games via `ManagedSettingsStore`.
- When games unlock, a DeviceActivity threshold equal to the earned minutes is armed; the
  monitor extension re-shields when it is reached (works while Zad X is closed).
- At each prayer time a 15-minute DeviceActivity interval starts; the extension shields games.
- On next launch, `AppLockPlugin` reports `prayer_lock` / `time_up` back to Flutter.

## Limits to know
- Per-minute usage cannot be read on iOS; the time budget is enforced by the threshold event.
- Opening a specific game from Zad X only works for games with a URL scheme (Roblox, Minecraft).
