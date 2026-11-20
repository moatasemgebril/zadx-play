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
  plan, planExpiresAt, inTrial, store, purchaseToken      (functions only)
  referralCode, referredBy, referralPaid, referrals{year}  (functions only)
  children/{childId}/days/{yyyy-MM-dd}   tasks progress, usedMinutes, prayerLock
  assistantUsage/{yyyy-MM-dd}            Basic plan daily AI quota
referralCodes/{CODE} → familyId
```

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
