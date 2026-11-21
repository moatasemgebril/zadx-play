# Decision: device-wide lock ("lock every app except an allowed list")

Status: **Proposed — agree with conditions** (zadx-cto-architect, 2026-11-21). Needs Quality Gate + owner sign-off.
Branch: `feat/device-wide-lock`.

## ملخص بالعربي

**السؤال:** هل الأفضل نقفل كل الألعاب والتطبيقات (فيسبوك، يوتيوب، المتصفح…) على الجهاز اللي عليه Zad X، مش بس قائمة ألعاب معيّنة؟

**رأي الفريق: موافقين بشروط.** القفل بـ "قائمة مسموحة" (كل حاجة مقفولة ما عدا تطبيقات معيّنة) أقوى بكتير من "قائمة ممنوعة"، لأن الطفل مش هيقدر يهرب لأي لعبة جديدة أو تطبيق تاني. الشروط:
1. التليفون والطوارئ يفضلوا شغالين **دايمًا** (ما ينفعش يتقفلوا أبدًا)، والرسائل/جهات الاتصال مسموحة افتراضيًا والأب/الأم يقدر يقفلها.
2. Zad X نفسه، شاشة البيت (اللانشر)، الكيبورد، وإعدادات الجهاز تفضل مفتوحة عشان الأمان.
3. الأب/الأم يقدر يضيف تطبيقات مسموحة (تطبيقات المدرسة، الكاميرا، الخرائط…).
4. لازم إفصاح واضح في Google Play و App Store، وبعدها اختبار على أجهزة حقيقية.
5. على الكمبيوتر (ويندوز) ما ننصحش نقفل "كل حاجة" لأنه خطر (ممكن يقفل الويندوز نفسه أو برامج الواجب)؛ بدل كده بنقفل الألعاب + المتاجر + المتصفحات + تطبيقات التواصل، والأب/الأم يقدر يسمح بالمتصفح للواجب.

الوقت المكتسب من المهام بقى يتحسب على **أي تطبيق مش مسموح** (مش الألعاب بس).

---

## 1. Context

Today the lock is a **block-list**:

| Platform | Mechanism | What is locked |
|---|---|---|
| Android | `AppBlockerService` (AccessibilityService, `typeWindowStateChanged` only, no window content) + `LockStore.isControlled(pkg)` | Package names of games the parent ticked in `lib/data/catalog/games.dart` |
| iOS | ManagedSettings shield from a `FamilyActivitySelection` the parent picks | Exactly the apps/categories picked |
| Windows | Zad X Guard service, `GameCatalog.cs` process names | Catalogue games (+ launchers) |

Bypass: the child opens **anything not on the list** — a new game from the store, a browser game, YouTube, TikTok, Facebook, a renamed APK. A block-list can never be complete; new games appear every day.

Owner request (2026-11-21): lock all games, Facebook and anything the child could play with on the device that has Zad X, for better control.

## 2. Options

| | Block-list (today) | Allow-list (proposed) |
|---|---|---|
| New/unknown game | Not locked | Locked by default |
| Browser / YouTube / social | Not locked | Locked unless allowed |
| Maintenance | Must track every game package / exe | Small stable list of system roles |
| Risk | Under-blocking | Over-blocking (must never block emergency/safety functions) |
| Data needed | Package names we ship | Package names of *system roles* resolved on-device; nothing leaves the device |

**Recommendation: allow-list ("allApps" mode) as the default; keep block-list as "selectedGames" legacy mode** for families who only want specific games locked (e.g. a teen's phone used for school).

## 3. Always-allowed list (never locked)

| Item | Why | How it is identified (Android) | Configurable |
|---|---|---|---|
| Phone / dialer, in-call UI | A child must always be able to call a parent | `TelecomManager.defaultDialerPackage` + `systemDialerPackage` (API 29+), `com.android.phone`, `com.android.server.telecom`, known in-call UIs | **No** |
| Emergency calls, emergency info, emergency alerts | Life safety; also a store-policy red line | `com.android.emergency`, Google Personal Safety, cell-broadcast receivers; emergency dialer runs in `com.android.phone` | **No** |
| SMS + contacts | Contact with parents | `Telephony.Sms.getDefaultSmsPackage`, `CATEGORY_APP_MESSAGING`, `CATEGORY_APP_CONTACTS` | Parent toggle (default **on**) |
| Zad X itself | The child must reach tasks, prayer and the "I prayed" flow to unlock | own package | No |
| Launcher (home screen, recents) | The shield sends the child HOME; blocking the launcher would loop and brick the phone | default HOME activity + system HOME apps | No |
| Keyboard (IME) | Needed to type in allowed apps; IME windows also fire window events | default IME + enabled **system** IMEs | No |
| System UI, `android` (dialogs/choosers), permission controller | Notification shade, lock screen, permission prompts | fixed package names | No |
| Settings | Wi-Fi, volume, accessibility needs, battery, SOS settings; a lock-out of Settings is a support and policy risk | `Settings.ACTION_SETTINGS` resolver + `com.android.settings` | No (see §6 owner decision) |
| Other enabled accessibility services | A child who uses TalkBack / Switch Access must keep them (disability access) | `ENABLED_ACCESSIBILITY_SERVICES` | No |
| Parent additions | School apps, camera, maps, calculator, Quran apps, WhatsApp to call family | parent picks from launchable apps (Android) / `FamilyActivityPicker` (iOS) | Yes |

Allowed apps never count play minutes. Everything else is locked while locked and **consumes earned minutes** while unlocked.

Third-party launchers/keyboards: only the *current default* launcher and *system* keyboards are trusted, so a "game keyboard" installed by the child is still locked. A child could still install a game that pretends to be a launcher and make it the default during unlocked time — residual risk R-37.

## 4. Platform feasibility

### Android — feasible now
- The existing AccessibilityService already receives the foreground package for **every** app; only `isControlled` changes. No new permission, no window-content access (`canRetrieveWindowContent=false` stays).
- Package visibility (Android 11+): we add **intent-based `<queries>`** (HOME, LAUNCHER, APP_MESSAGING, APP_CONTACTS, SETTINGS) instead of `QUERY_ALL_PACKAGES`. The LAUNCHER query is what lets the parent pick apps to allow.
- Logic lives in a pure Kotlin object (`LockRules.kt`), mirrored by `lockRuleControls()` in Dart for unit tests.
- **Disabling the service from Settings** is the main bypass (already R-04). Options considered:
  - Block Settings while locked: rejected as default (safety/accessibility, Play policy, parent lock-out). Offered as an owner decision.
  - Device Admin for uninstall protection: technically possible and used by parental-control apps, but Play's Device Admin and "Unwanted Software" rules require clear disclosure and easy removal by the parent; it does not stop disabling Accessibility. **Not in this PR**; follow-up with a separate disclosure.
  - Tamper detection (service disabled → push to parent): recommended P1 follow-up (R-04).
  - Strongest option: guide parents to Google Family Link (supervised account) for uninstall/settings protection.

### iOS — feasible now (needs real-device verification)
- `ManagedSettingsStore.shield.applicationCategories = .all(except: allowedAppTokens)` and `shield.webDomainCategories = .all(except: allowedWebTokens)`.
- Allowed apps are chosen by the parent in Apple's `FamilyActivityPicker` (opaque tokens; iOS never reveals which apps are installed — good for privacy).
- Apple keeps Phone/emergency calls (SOS) available; Screen Time cannot shield them. Whether Zad X itself is shielded by `.all` must be checked on a device: the parent UI tells the parent to include Zad X in the allowed selection, as a safe default.
- Time budget: `DeviceActivityEvent` cannot express "all apps"; the budget keeps counting the parent's existing "apps that use play time" selection (recommend: Games + Social + Entertainment categories). Documented limitation.
- Revocation: with `.individual` authorization the child can turn Screen Time access off (R-13); `.child` via Family Sharing is the recommended setup.

### Windows — limited scope recommended
Blocking every process except an allow-list on a PC is **too risky**: Windows runs hundreds of system and helper processes, Office/Teams/WebView2 hosts, drivers, accessibility tools, and homework software; a mistake can make the PC unusable or kill a parent's admin session. Recommended scope for "allApps" mode on Windows:
- catalogue games + game launchers (as today) **+ browsers** (closes browser games, YouTube, Facebook web) **+ social/chat apps** (Discord, Telegram, WhatsApp, etc.).
- Parent switch "allow browsers on the PC" for homework (default off). `msedgewebview2` is never touched (used by Windows itself).
- A full "lock session" (sign the child out) is a possible later step and should use Microsoft Family Safety screen-time instead of our own code.

## 5. Store policy and disclosures

| Store | Risk | What we must do |
|---|---|---|
| Google Play — Accessibility API | Using Accessibility for non-accessibility purposes needs the Permissions Declaration Form and a **prominent in-app disclosure** before sending the user to settings; the use case must be parental control and clearly described | Update disclosure text: "Zad X sees which app is open on this phone (only the app name, never what is on the screen) to lock apps until tasks and prayers are done. Phone and emergency calls are never locked." Update Data safety: app activity → "App interactions" processed on-device only, not collected. |
| Google Play — package visibility | Broad visibility needs justification | Intent queries only; no `QUERY_ALL_PACKAGES`. Mention in the declaration that LAUNCHER visibility is used for the parent's allow-list. |
| Google Play — Families | Parent-facing controls must be behind the parent gate; child-facing app must not collect app-usage data | Allow-list editor is inside the PIN-protected parent screen; installed-app list never leaves the device. |
| Apple — FamilyControls | Distribution entitlement; data from the Screen Time API must not leave the device / be used for anything other than the parental-control feature | Tokens stay in the App Group; nothing is uploaded. Review notes must explain that all-but-allowed shielding is parent-initiated. |
| Apple 5.1.4 / COPPA / GDPR-K | Kids' data | No new data collected or sent; Windows settings sync only sends `lockMode` and a boolean. |

## 6. Security review (bypass vectors)

| Vector | Block-list | Allow-list |
|---|---|---|
| Install/open a new game | Bypassed | Locked |
| Browser / YouTube / social | Bypassed | Locked (unless parent allows) |
| Rename / clone APK | Bypassed | Locked (unknown package) |
| Disable Accessibility in Settings | Bypassed | **Still bypassed** → R-04 tamper alert, Family Link |
| Third-party keyboard / launcher with games | Bypassed | Keyboard: locked (not system). Launcher: residual R-37 |
| Split screen / pop-up window | Fixed (R-22) | Same |
| iOS: revoke Screen Time | R-13 | R-13 |
| Windows: renamed game exe | R-09 | R-09 (browsers/social reduce it, do not remove it) |
| Windows: allowed browser used for games | n/a | Parent's choice; documented |

**Owner decisions** (not blocking this PR):
1. Lock the Settings app while locked (quick settings stay)? Team recommends **no** until tamper alerts exist.
2. Optional Device Admin uninstall protection (separate disclosure) — team recommends a later PR.
3. Make Family Link / Family Sharing setup a step in parent onboarding.

## 7. UX (children and parents)
- Child: one consistent rule — "finish tasks / pray → phone opens". The shield says "apps" instead of "games" in allApps mode; it always offers "Open Zad X". Phone calls never blocked.
- Parent: one switch "Lock all apps (recommended)" on the parent screen, a read-only "always allowed" list so they trust it, and an editor to add apps. The game chips stay (they choose which games appear in Zad X's Games screen and are the lock list in legacy mode).
- Time semantics change: earned minutes become **screen minutes** for all non-allowed apps. Copy must say this plainly.

### Plans without tasks (Free)
Free families have no tasks/earned minutes, so the task rule would keep a Free child locked all day.
`lockStateFor(tasksEnabled: false, …)` uses only the **prayer lock + a parent-set daily limit**
(`dailyLimitMinutes`, default 60; chips 30–180 on the parent screen).
`lockTasksEnabledProvider` = `hasFeature(plan, tasksRewards)` (Basic, Plus and the 7-day trial: true; Free: false).

How the prayer lock ends on Free (owner decision 2026-11-21): there is no "I prayed" task to approve, so the
lock **ends by itself 20 minutes after it started** (`freePrayerLockWindow` =
`AppConfig.playWindowAfterPrayerMinutes`). The start time is kept in the wallet (`prayerLockSince`, synced as
`prayerLockSinceMs`); a lock saved without a start time counts from when the app reads it, so it always ends
after at most one window. Paid plans keep the current rule (parent approves "I prayed").
`LockPolicy.prayerAutoEndMinutes` (20 on Free, 0 on paid) is sent to native code so the Android/iOS blockers
can end the lock without Zad X running (native follow-up, other branch). Until then, the lock ends when Zad X
next runs (the child can always open Zad X).
Residual: on Free a child who moves the device clock forward ends the 20-minute lock early (Dart has no
monotonic clock across restarts; native can use `elapsedRealtime`).

## 8. Islamic-content priority
Device-wide locking supports the product's core value (prayer before play) more faithfully: at adhan time every distraction is locked, not only known games. Zad X's Quran, adhkar and prayer sections remain open because Zad X is always allowed; parents can also allow a trusted Quran app. No religious text is added or changed by this work.

## 9. Verdict
**Agree with conditions.** Top reasons:
1. A block-list cannot keep up with new games, browsers and social apps; an allow-list closes the main bypass the owner described.
2. It is feasible on Android and iOS with the permissions we already have (no new data, no new Play-restricted permission); Windows gets a safe, wider scope instead of a risky "block everything".
3. Child safety is preserved by an always-allowed core (phone, emergency, parent contact, Zad X, launcher, keyboard, settings) that cannot be removed.

Conditions: updated store disclosures (§5), real-device tests (Android 10/14, Samsung + Pixel; iPhone with `.child` authorization), R-04 tamper alert as a P1 follow-up, and owner sign-off on §6 decisions.

Note for billing: `maxGames` (plan limit on the number of locked games) has no meaning in allApps mode; it still limits the games shown in the Games screen / legacy mode. Plan copy should be revisited by the subscription owner.
