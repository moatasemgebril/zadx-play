# Zad X backend (Firebase)

## Setup
```bash
npm i -g firebase-tools
firebase login
firebase use --add            # pick/create the Zad X project
cd functions && npm install && npm run build
firebase functions:secrets:set ANTHROPIC_API_KEY   # from console.anthropic.com
npm run deploy
```

In the Flutter app run `flutterfire configure` (adds google-services.json / GoogleService-Info.plist).

## Data model
```
families/{familyId}
  members: [uid]            parents + paired child devices
  parentTokens: [fcmToken]
  language, settings{notifyOnTasks, notifyOnAdhan}
  plan, planExpiresAt, inTrial, store                    (functions only; every member reads them)
  private/billing { purchaseToken }                      (functions only, no client access)
  referralCode, referredBy, referralPaid, referrals{year}  (functions only)
  children/{childId}/days/{yyyy-MM-dd}   tasks progress, usedMinutes, prayerLock
  assistantUsage/{yyyy-MM-dd}            Basic plan daily AI quota
referralCodes/{CODE} → familyId
purchases/{sha256(store token)} → familyId, store   (functions only: one purchase = one family)
```

`parentDevices: {uid: linkedAt}` on the family doc records phones linked with a parent code (functions only).

## One-off migration: purchase tokens (run before/at the deploy of fix/family-entitlement-restore)
Older family docs may still hold the raw `purchaseToken`, which every member (child devices
included) can read. Right before or together with that deploy, run once against the Zad X project:
```
cd backend/functions && npm run build
GOOGLE_APPLICATION_CREDENTIALS=<admin key, never committed> node scripts/migrate-purchase-tokens.js           # dry run
GOOGLE_APPLICATION_CREDENTIALS=<admin key, never committed> node scripts/migrate-purchase-tokens.js --apply
```
It moves each token to `purchases/{sha256}` + `families/{id}/private/billing` and deletes the field
(idempotent). Exit code 2 = a token already owned by another family: left unchanged, check by hand.

## Store webhooks
- **Google Play**: Play Console → Monetization setup → Real-time developer notifications →
  Pub/Sub topic with a push subscription to the `playNotifications` URL.
  Give the Functions service account access in Play Console → API access.
- **App Store**: App Store Server Notifications v2 → add an `appStoreNotifications`
  endpoint (TODO) and verify receipts with `@apple/app-store-server-library`.

## Referral rules (enforced here, not in the app)
- A friend counts only after their **first paid period** (not the free trial).
- Max 3 friends per year → 2 / 4 / 6 free months.
- Android: the referrer's subscription is extended with `subscriptions.defer`.
- iOS: send a one-time **offer code** (TODO).
