# Decision: device protection ("Settings for the parent only", prevent deleting Zad X, tamper alerts)

Status: **Owner decided 2026-11-21**; implementation on branch `feat/device-protection` (needs Quality Gate,
real-device tests and store-declaration updates before release).
Builds on docs/decisions/DEVICE-WIDE-LOCK.md. Risks: R-04, R-39, R-42..R-45 in security/RISK-REGISTER.md.

## ملخص بالعربي

- **الإعدادات لولي الأمر بس:** على أندرويد تطبيق الإعدادات مقفول على الطفل طول الوقت (مش بس وقت القفل). ولي الأمر
  يفتحه من Zad X بالرقم السري لمدة ٥ دقايق وبعدها يتقفل لوحده. أي خطوة في Zad X بتودّي ولي الأمر للإعدادات (إمكانية
  الوصول، مدير الجهاز…) بتفتح المدة دي تلقائي بعد الرقم السري. التليفون ومكالمات الطوارئ وSOS عمرهم ما بيتقفلوا.
- **منع مسح Zad X:** على أندرويد بنغطّي شاشة "إلغاء التثبيت" + "مدير الجهاز" اختياري (من غير أي صلاحيات تانية)، فأندرويد
  نفسه بيرفض مسح Zad X. على الآيفون: Screen Time بيمنع مسح التطبيقات (كل التطبيقات، مش Zad X بس). على الكمبيوتر:
  الخدمة محمية ومحدش غير الأدمن يقدر يوقفها.
- **تنبيه التلاعب:** لو الحماية اتقفلت أو الجهاز بطّل يتواصل يوم كامل، يوصل إشعار لتليفون ولي الأمر.
- **الآيفون مش بيسمح بقفل تطبيق الإعدادات نفسه** — بنقفل الحسابات والرقم السري للجهاز والتاريخ والساعة بس.

## What each platform can and cannot enforce

| | Android | iOS | Windows |
|---|---|---|---|
| Lock the Settings app for the child | **Yes** — AccessibilityService covers `com.android.settings`, settings search, Xiaomi security center and the package resolved from `ACTION_SETTINGS`, at all times, unless the parent PIN window is open (5 min, max 10, bound to elapsed time + boot count) | **No** (Apple does not allow it). Instead: `account.lockAccounts`, `passcode.lockPasscode`, `dateAndTime.requireAutomaticDateAndTime` | Optional per-user policy "Prohibit access to Control Panel and PC settings" on the child's Standard account (`child_settings_lock.ps1`); no PIN window — parent uses their admin account |
| Quick-settings long-press into Settings | Covered (it opens the Settings package) | n/a | Taskbar quick settings stay usable |
| Never block emergency | Phone, telecom, in-call UI, emergency info, Personal Safety, Samsung SOS, cell broadcast, system UI, permission controller are checked **before** the Settings rule | Apple keeps calls/SOS available | n/a |
| Prevent uninstall | Uninstall dialog covered while "Prevent deleting Zad X" is on (class name only → covers uninstalling **any** app); optional Device Admin with **no policies** makes Android refuse to uninstall Zad X | `application.denyAppRemoval = true` (all apps; no per-app option) | Service DACL: only SYSTEM/Administrators can stop, reconfigure or delete it; uninstall needs admin |
| Stop the child turning protection off | Settings is locked, so the accessibility service and Device Admin cannot be switched off without the PIN. **Residual:** safe-mode boot disables third-party accessibility services | With `.child` (Family Sharing) authorization removal needs the parent. **Residual:** `.individual` can be revoked by the child (R-13) | Standard user cannot stop the service. **Residual:** an administrator can |
| Tamper alert | `accessibility_off`, `device_admin_off` reported on start/resume; 24 h silent → alert | `screen_time_off` reported on start/resume; 24 h silent → alert | Guard heartbeat via `devicePolicy`; 24 h silent → alert |

## Design

### Android
- Pure rules in `LockRules.kt`: `protectionGuard`, `isUninstallUi`, `isParentWindowOpen`, `tamperReasons`
  (JUnit `LockRulesTest`, run in CI; Dart mirror `protectionGuardFor` / `protectionTamperReasons` in
  `lib/services/app_lock/lock_rules.dart`, tested in `test/device_protection_test.dart`).
- `AppBlockerService` checks protection **before** the app lock, in every lock mode and lock state. It still reads
  only the package and class name (`canRetrieveWindowContent=false`); the uninstall guard therefore cannot tell which
  app is being removed and covers all uninstall dialogs while on. This keeps the disclosure promise.
- Parent window: `LockStore.openParentWindow` stores `elapsedRealtime + minutes` and `Settings.Global.BOOT_COUNT`;
  a moved wall clock or a reboot cannot extend it.
- Flows that open Settings: `requestPermissions` (Accessibility) opens the window itself when the service is not on yet
  (nothing is protected then); every other flow goes through `openSettingsForParent` / the Protection card, which
  asks for the PIN again (`confirmParentPin`, same throttle as the parent gate) and then opens the window.
- Device Admin: `ZadXDeviceAdminReceiver`, `res/xml/zadx_device_admin.xml` with empty `<uses-policies>`. Enabled
  only after PIN + prominent disclosure; disabled from Zad X after PIN (`removeActiveAdmin`, not reported as tamper).
- Recovery for a parent who forgot the PIN: boot into safe mode (third-party accessibility services do not run),
  open Settings, turn Zad X off. Documented for support; not shown in the child-facing UI.

### iOS
- `SharedStore.applyProtection` writes a separate `ManagedSettingsStore("zadx.protection")`, so clearing the app
  shield never clears protection. Applied only when FamilyControls is approved.

### Windows
- `install.ps1` → `sc sdset` (SY + BA control; AU/IU query only). `child_settings_lock.ps1` (optional, refuses admin
  accounts, `-Unlock` to undo). We do not kill `SystemSettings.exe` from the guard: unsafe and unsupported.

### Tamper alerts (backend)
- `reportProtection` (callable): child devices send `{platform, reasons[]}` (reason codes only). Stored in top-level
  `deviceHeartbeats` (Functions only). Newly appeared reasons → one FCM push to `parentTokens`.
- Windows guard: `authenticateDevice` refreshes its heartbeat at most every 30 minutes.
- `checkHeartbeats` (Cloud Scheduler, every 6 h): one "not checking in" push per device silent for 24 h.
  Uses one Cloud Scheduler job (free tier covers 3 jobs per billing account) — no new paid service.
- Push text never contains the child's name.

## Not done / follow-ups
- Native periodic self-check on Android (so a disabled service is reported without opening Zad X).
- Alert when the default launcher or enabled accessibility services change (R-37).
- Parent onboarding step for Google Family Link / Apple Family Sharing (strongest OS-level protection).
- Real-device matrix (STORE_CHECKLIST) incl. OEM Settings package names.

## Free plan: prayer lock ends on its own natively (coordinator task, 2026-11-21)
- Flutter sends `prayerAutoEndMinutes` (Free = the free prayer window, paid = 0) and `prayerLockSinceMs` in the policy.
- **Android** (`LockRules.prayerRemainingMs`, `prayerAnchorAction`, `shouldBlock`; JUnit `PrayerAutoEndTest`):
  the timer is anchored to `SystemClock.elapsedRealtime()` when the lock starts (adhan alarm, or the first policy
  for a new lock; `prayerLockSinceMs` only identifies the lock, it is never used for timing). After a reboot it
  falls back to the wall clock but never below the remaining time last seen before the reboot, and never above one
  window. A late policy for a lock that already ended natively is ignored.
- **iOS**: the prayer DeviceActivity interval is scheduled `max(15, prayerAutoEndMinutes)` long; `intervalDidEnd`
  in ZadXMonitor lifts the prayer shield (keeps it if no minutes are left) and restarts the daily budget monitor.
  iOS runs the schedule; with device protection on, `requireAutomaticDateAndTime` stops the child moving the clock.
  Without protection, a clock change could shift the schedule (documented residual).

## Quality Gate fixes (2026-11-21)
- Play Store purchase-sheet exemption (`LockRules.playSheetExempt`): only within 2 minutes of Zad X being in the
  foreground and only for Play windows that follow Zad X directly (or an exempt Play window); `lastForeground` is set to
  the Play Store after an exempt event, so later Play visits are locked/metered normally. Residual: a child bouncing
  Zad X → Play Store every 2 minutes can browse the store (not play), which is bounded and visible.
- `checkHeartbeats`: deletes heartbeats of deleted families/children and any older than 30 days; queries only
  `staleAlerted == false` (composite index in `backend/firestore.indexes.json`, deployed with `firestore:indexes`),
  so alerted docs cannot starve new ones. `reportProtection`: same reason from the same device pushed at most once per hour.
- `isControlled`: the safety core and device roles are checked before the legacy game list in every mode.
- `settingsPackages()` never includes the default/system dialer or the default SMS app.
- Free-plan shield text: "Apps are locked for prayer time — they open again soon" / «التطبيقات مقفولة وقت الصلاة، وهتفتح بعد شوية».
