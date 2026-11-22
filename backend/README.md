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
  children/{childId}/days/{yyyy-MM-dd}   progress (child submissions), usedMinutes, prayerLock, prayerLockAt
                                         approved{taskId: minutes}, earnedMinutes, requiredDone  (approveTask only)
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
- **App Store** (`verifyPurchase` on iOS + `appStoreNotifications`, `src/apple.ts` / `src/apple-logic.ts`):
  every signed transaction / notification is verified with `SignedDataVerifier`
  (`@apple/app-store-server-library`: JWS signature, x5c chain up to Apple's root CA, bundle id
  `com.zadx.app`, environment, OCSP), the tier comes from the verified productId, and the current
  state is read from the App Store Server API. **Fails closed** (no entitlement, clear log line
  naming the missing settings) until all of this is configured:
  ```bash
  # App Store Connect → Users and Access → Integrations → In-App Purchase → generate a key (.p8)
  firebase functions:secrets:set APPLE_PRIVATE_KEY --data-file SubscriptionKey_XXXXXXXXXX.p8
  # functions/.env (or .env.<project>): params, not secrets
  APPLE_ENVIRONMENT=Sandbox            # Production for the live app
  APPLE_ISSUER_ID=<issuer id shown above the keys list>
  APPLE_KEY_ID=<the key id>
  APPLE_APP_APPLE_ID=<numeric Apple ID, App Store Connect → App Information>  # required in Production
  # Apple's public root certificates into functions/certs/ (checked against Apple's page; commit them)
  bash scripts/fetch-apple-root-certs.sh
  ```
  App Store Connect → App Information → App Store Server Notifications → Version 2, Production and
  Sandbox URL = the deployed `appStoreNotifications` URL (europe-west1).
  `verifyPurchase` lists `APPLE_PRIVATE_KEY` as a secret, so the secret must exist before deploying
  (set it to `unset` to deploy before the key exists: iOS then fails closed).

## Referral rules (enforced here, not in the app)
- A friend counts only after their **first paid period** (not the free trial).
- Max 3 friends per year → 2 / 4 / 6 free months.
- Android: the referrer's subscription is extended with `subscriptions.defer`.
- iOS: send a one-time **offer code** (TODO).
