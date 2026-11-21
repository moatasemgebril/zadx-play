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
- [ ] Pre-launch blocker: no reciter licence confirmed in writing yet (flag licenceConfirmed in lib/data/catalog/quran.dart)
- [ ] Game icons are our own; never ship publishers' logos or screenshots.

## Apple
- [ ] Family Controls **Distribution** entitlement approved.
- [ ] App Group + extensions signed; test on a real device with a child Apple ID in Family Sharing.
- [ ] Subscriptions created: zadx_basic_monthly / yearly, zadx_plus_monthly / yearly, 14-day intro offer.
- [ ] App Store Server Notifications v2 endpoint.

## Google
- [ ] Permissions Declaration Form for the Accessibility API (parental control use case).
- [ ] Prominent disclosure screen before opening Accessibility settings (explain we only detect which game opens).
- [ ] Exact alarm usage justification (prayer locks).
- [ ] Verify every game package name in `lib/data/catalog/games.dart` and the manifest `<queries>`.
- [ ] Subscriptions + base plans + 14-day free trial offer tagged `trial`; RTDN Pub/Sub → `playNotifications`.

## Windows (Zad X Guard)
- [ ] Code-sign the executable (Authenticode certificate) and ship an MSI/MSIX installer.
- [ ] Host the installer at `AppConfig.windowsGuardDownload`.
- [ ] Verify game process names in `windows_guard/GameCatalog.cs`.
- [ ] Explain to parents that the child must use a Standard (non-admin) Windows account.

## Consoles
- [ ] PlayStation Family (Android package `com.playstation.ohana.android`) and Microsoft Family Safety
      (`com.microsoft.familysafety`) open correctly from the Parent screen.

## Business
- [ ] Final prices per country (Play/App Store price tiers), e.g. lower tiers for Egypt, India, Pakistan.
- [ ] Referral terms page (friend must pay after trial; max 6 free months/year).
- [ ] Anthropic API key with a spend limit; Basic plan quota (10 questions/day) tuned to budget.
