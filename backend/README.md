# Zad X backend (Firebase)

## Setup
```bash
npm i -g firebase-tools
firebase login
firebase use --add            # pick/create the Zad X project
cd functions && npm install && npm run build
firebase functions:secrets:set ANTHROPIC_API_KEY   # from console.anthropic.com
firebase functions:secrets:set APPLE_PRIVATE_KEY   # the .p8 key, or type `unset` for now (iOS fails closed)
```
Then deploy with the **Deploy runbook** below (never rules and functions in one step).

## Deploy runbook (functions first, rules last)
`npm run deploy` is disabled on purpose; it prints this order and stops.

1. **Secrets exist.** `APPLE_PRIVATE_KEY` must exist before any functions deploy, because
   `verifyPurchase` / `appStoreNotifications` declare it. Until the App Store key is ready, set it to
   the text `unset` (`firebase functions:secrets:set APPLE_PRIVATE_KEY`, then type `unset`): iOS
   purchases then fail closed. `npm run deploy:functions` checks the secret first
   (`firebase functions:secrets:get`, shows versions only, never the value) and stops if it is missing.
2. **Deploy functions (+ indexes):** `cd backend/functions && npm run deploy:functions`.
   Safe with the current app builds: old builds keep writing as before, and the new callables
   (`approveTask`, `rejectTask`) are simply not called yet.
3. **Ship the new app and require testers to update.** Publish the build that calls `approveTask`
   (Play internal testing / TestFlight / web preview) and ask every tester family to update **both** the
   parent phone and the child devices. Older builds write `earnedMinutes` / `prayerLockSinceMs`
   themselves; after step 4 the rules refuse those writes, so their sync stops until they update.
4. **Deploy rules:** `npm run deploy:rules` (only after step 3 is done).
5. **Check:** on a test family, approve a task from the parent phone (minutes appear on the child),
   and confirm a child device cannot end a prayer lock early.

Rollback: re-deploy the previous `firestore.rules` first (`git checkout <previous> -- backend/firestore.rules
&& npm run deploy:rules`), then functions if needed.

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
  children/{childId}/days/{yyyy-MM-dd}   progress (child submissions), usedMinutes, prayerLock, prayerLockAt (server time)
                                         prayerLockSinceMs: legacy device time, no client may write it
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
  (`@apple/app-store-server-library`: JWS signature, x5c chain up to Apple's root CA, bundle id,
  environment, OCSP), the tier comes from the verified productId, and the current
  state is read from the App Store Server API. **Per app:** a purchase is verified against the
  bundle of the app whose product id was sent (Zad X Play `com.zadx.app`, Zad X Kids
  `com.zadx.kids`), and only that app's product ids grant a tier (`tierForApp`). Plans are stored
  under `plans.<app>`; the legacy top-level `plan / planExpiresAt / inTrial` (+ `planApp`) are
  written for Zad X Play only. The billing doc stores the ownership key (`apple:<originalTransactionId>`,
  never the raw receipt), `storeApp` and the verified product id. `appStoreNotifications` (one URL
  for both apps) finds the app by which bundle's verifier accepts the signed payload. **Fails closed** (no entitlement, clear log line
  naming the missing settings) until all of this is configured:
  ```bash
  # App Store Connect → Users and Access → Integrations → In-App Purchase → generate a key (.p8)
  firebase functions:secrets:set APPLE_PRIVATE_KEY --data-file SubscriptionKey_XXXXXXXXXX.p8
  # functions/.env (or .env.<project>): params, not secrets
  APPLE_ENVIRONMENT=Sandbox            # Production for the live app
  APPLE_ISSUER_ID=<issuer id shown above the keys list>
  APPLE_KEY_ID=<the key id>
  APPLE_APP_APPLE_ID=<numeric Apple ID of Zad X Play, App Store Connect → App Information>  # required in Production
  APPLE_KIDS_APP_APPLE_ID=<numeric Apple ID of Zad X Kids>   # required in Production once Kids is on the App Store
  # Apple's public root certificates into functions/certs/ (checked against Apple's page; commit them)
  bash scripts/fetch-apple-root-certs.sh
  ```
  App Store Connect → App Information → App Store Server Notifications → Version 2, Production and
  Sandbox URL = the deployed `appStoreNotifications` URL (europe-west1), for **both** apps.
  `verifyPurchase` lists `APPLE_PRIVATE_KEY` as a secret, so the secret must exist before deploying
  (set it to `unset` to deploy before the key exists: iOS then fails closed).

## Referral rules (enforced here, not in the app)
- A friend counts only after their **first paid period** (not the free trial).
- Max 3 friends per year → 2 / 4 / 6 free months.
- Android: the referrer's subscription is extended with `subscriptions.defer`.
- iOS: send a one-time **offer code** (TODO).

## Firestore rules tests (R-32 / R-33)
`functions/test/rules.test.js` runs against the Firestore emulator in the CI `backend` job (every PR).
Locally (Java 11+ and `npm i -g firebase-tools@14`), from `backend/functions`:
`npm run test:rules:deps && npm run test:rules`. The test SDKs are installed with `--no-save`, so
`npm audit` in CI covers only the deployed dependencies. Run them after any change to `firestore.rules`.
