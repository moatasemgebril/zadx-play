# Before publishing — checklist

## Name & listing
- [ ] Confirm "Zad X Play" is free on App Store Connect and Google Play (and not a registered trademark in your category).
- [ ] Subtitle (AR): ألعاب بعد الصلاة والمهام — (EN): Games after prayer & tasks
- [ ] Category: Lifestyle or Education (not Kids Category if the parent is the main user; read Apple 1.3 / Play Families policy).
- [ ] Privacy policy URL + data safety form (location for prayer times, FCM tokens, anonymous auth).

## Content
- [ ] A qualified scholar reviews all adhkar texts and counts (`lib/data/catalog/adhkar.dart`).
- [ ] Quran text source attribution (Quran.com / Tanzil) as their terms require.
- [ ] Licensed adhan recordings (written permission or royalty-free licence) for each muezzin.
- [ ] Confirm the reciters' audio may be streamed in a paid app (or host your own licensed files).
- [x] Reciter licences: Quran Foundation approved Alafasy, Abdul Basit (murattal), Al-Husary, Al-Minshawi (murattal) in writing on 2026-11-21 (flag licenceConfirmed in lib/data/catalog/quran.dart). Abdur-Rashid Sufi is NOT approved.
- [ ] Pre-launch blocker: switch recitation audio from EveryAyah URLs to the Quran Foundation recitations API (approval covers QF APIs only; no rehosting, max 1-week server cache; device download for offline is allowed).
- [ ] Show "Quran data provided by Quran Foundation" + credit each reciter in the app.
- [ ] Game icons are our own; never ship publishers' logos or screenshots.

## Device-wide lock (docs/decisions/DEVICE-WIDE-LOCK.md)
- [ ] Store listings + privacy policy say plainly: "Zad X can lock all apps on the child's device except the
      apps the parent allows. Phone and emergency calls are never locked."
- [ ] Data safety (Play) / App Privacy (Apple): which app is open is processed **on the device only** and is not
      collected or shared; the installed-app list used by the parent's allow-list never leaves the device.
- [ ] Real-device tests before release: Pixel + Samsung (Android 10 and 14), iPhone with `.child` authorization:
      emergency call while locked, incoming call while locked, keyboard, home/recents, Play purchase sheet from
      Zad X, TalkBack on, Zad X opens while shielded (iOS: Zad X in the allowed selection).

## Apple
- [ ] Family Controls **Distribution** entitlement approved.
- [ ] App Review notes: "all apps except allowed" shielding (`.all(except:)`) is turned on by the parent behind a
      PIN; Screen Time tokens stay in the App Group and are never uploaded.
- [ ] Device protection on iOS: `denyAppRemoval` (blocks deleting **all** apps while on), `lockAccounts`,
      `lockPasscode`, `requireAutomaticDateAndTime` from a separate `ManagedSettingsStore("zadx.protection")`.
      Review notes: parent-enabled, no data leaves the device. Test with `.child` authorization.
- [ ] App Group + extensions signed; test on a real device with a child Apple ID in Family Sharing.
- [ ] Subscriptions created: zadx_basic_monthly / yearly, zadx_plus_monthly / yearly, 14-day intro offer.
- [ ] App Store Server Notifications v2 endpoint.

## Google
- [ ] Permissions Declaration Form for the Accessibility API (parental control use case). Describe the device-wide
      lock: only the package name of the foreground app is read (`canRetrieveWindowContent=false`), to lock every app
      except phone/emergency, Zad X, launcher, keyboard, settings, messaging (parent choice) and parent-allowed apps.
- [ ] Prominent disclosure screen before opening Accessibility settings. Text (AR/EN, reviewed by legal): "Zad X sees
      which app is open on this phone (only the app's name, never what is on the screen) so it can lock apps until
      tasks and prayers are done. Phone and emergency calls are never locked. Nothing about the apps used leaves
      this phone."
- [ ] Package visibility: intent `<queries>` only (LAUNCHER, HOME, APP_MESSAGING, APP_CONTACTS, SETTINGS); **no**
      `QUERY_ALL_PACKAGES`. Be ready to justify LAUNCHER visibility as the parent's allow-list editor.
- [ ] **Device protection** (docs/decisions/DEVICE-PROTECTION.md). Update the Accessibility declaration: the same
      service (package + class name only, never screen text) also keeps the **Settings app for the parent only**
      (opened for 5 minutes with the parent PIN) and, when the parent turns it on, covers the **system uninstall
      dialog**. Phone, emergency and SOS are never covered. The in-app disclosure now adds: "Zad X also keeps the
      phone's Settings app for you only (you open it with your PIN) and can stop apps being deleted without you."
- [ ] **Device Admin (optional, parent-enabled) — Play disclosure text.** Use in the Permissions Declaration /
      review notes and the store listing:
      > "Zad X is a parental-control app. If the parent turns on *Prevent deleting Zad X*, Zad X asks to become a
      > device admin app. It requests **no device-admin policies** (no wipe, lock, password, camera or encryption
      > control); being active only makes Android refuse to uninstall Zad X. Before Android's activation screen the
      > parent sees a prominent disclosure explaining this, and must enter the parent PIN. The parent can turn it
      > off at any time in Zad X (PIN) and Android always lets it be removed in Settings → Security → Device admin
      > apps."
      Check the current Play Developer Program Policy (Device and Network Abuse, Unwanted Software, Families)
      wording before submission; legal review of the AR/EN text.
- [ ] Device Admin activation screen shows `protectAdminExplanation`; `res/xml/zadx_device_admin.xml` has an empty
      `<uses-policies>` (verify in the merged APK manifest).
- [ ] Real-device protection tests (Pixel + Samsung + one Xiaomi, Android 10 and 14): Settings blocked for the
      child; quick-settings tile long-press into Settings blocked; settings search blocked; PIN opens 5 minutes then
      re-locks; Accessibility setup flow from Zad X is not interrupted; Device Admin activation and removal from
      Zad X; uninstall from the launcher and from Play blocked while on; emergency call / power-button SOS /
      emergency info still work while Settings is locked; safe-mode recovery for a parent who forgot the PIN.
- [ ] Exact alarm usage justification (prayer locks).
- [ ] Verify every game package name in `lib/data/catalog/games.dart` and the manifest `<queries>`.
- [ ] Subscriptions + base plans + 14-day free trial offer tagged `trial`; RTDN Pub/Sub → `playNotifications`.

## Windows (Zad X Guard)
- [ ] Code-sign the executable (Authenticode certificate) and ship an MSI/MSIX installer.
- [ ] Host the installer at `AppConfig.windowsGuardDownload`.
- [ ] Verify game, browser and social process names in `windows_guard/GameCatalog.cs` (never add `msedgewebview2`).
- [ ] Tell parents: in "lock all apps" mode the PC closes games, launchers, social apps and (unless allowed)
      browsers; it does not lock every program.
- [ ] Explain to parents that the child must use a Standard (non-admin) Windows account.
- [ ] Test `install.ps1` service ACL (a Standard user gets "Access is denied" for `sc stop ZadXGuard`) and
      `child_settings_lock.ps1` on Windows 10 and 11 (lock + `-Unlock`, refuses admin accounts).

## Consoles
- [ ] PlayStation Family (Android package `com.playstation.ohana.android`) and Microsoft Family Safety
      (`com.microsoft.familysafety`) open correctly from the Parent screen.

## Business
- [ ] Store listing and screenshots show the three offers: Free forever (app lock, prayer times, adhan, Quran),
      Basic and Plus (feature table in docs/ARCHITECTURE.md "Plans"). No subscription product is created for Free.
- [ ] App Review / Families notes: purchase screens and upgrade prompts are behind the parent PIN.
- [ ] Final prices per country (Play/App Store price tiers), e.g. lower tiers for Egypt, India, Pakistan.
- [ ] Referral terms page (friend must pay after trial; max 6 free months/year).
- [ ] Anthropic API key with a spend limit; Basic plan quota (10 questions/day) tuned to budget.
