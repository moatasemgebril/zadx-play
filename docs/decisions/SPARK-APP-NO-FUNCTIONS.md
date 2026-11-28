# Zero-cost backend: app side without Cloud Functions

Owner decision 2026-11-28: zero technical cost forever. Firebase stays on the free Spark plan (Auth,
Firestore, Hosting). No Cloud Functions, no secrets server, no card. This page covers the app-side
part (branch `feat/spark-no-functions-app`): billing, the AI assistant, parent alerts, heartbeats and
referrals. The family core (pairing, device removal, membership, task approval, free child) moves to
Firestore rules in a separate branch.

## One switch: `FeatureFlags.serverFunctions`

`lib/core/feature_flags.dart`. It is **off** by default in every build. While it is off:

- The app never calls a Cloud Function for this scope. All of these calls go through one gateway,
  `lib/core/server_functions.dart` (`ServerCalls`). The default `DisabledServerCalls` fails with
  `ServerFunctionsDisabled` and never touches Firebase Functions.
- `FeatureFlags.assistant` and `FeatureFlags.referralRewards` are off as well. Each one needs
  `serverFunctions` **and** its own define.

If the owner ever chooses Blaze, a build with `--dart-define=ZADX_SERVER_FUNCTIONS=true` turns the old
server paths back on (`verifyPurchase`, `notifyParent`, `reportProtection`). The assistant also needs
`ZADX_ASSISTANT=true` and the referral card needs `ZADX_REFERRALS=true`.

## 1. Purchases: trusted on the device that bought them

`lib/services/billing/device_entitlement.dart`, `subscription_service.dart`

- **Google Play.** On every Android launch, a restore returns only the subscriptions that are active
  now. Each one grants its tier until *now + 7 days* (rolling), so a cancelled subscription ends at
  most 7 days after the last launch that still saw it.
- **App Store (iOS / macOS).** The plan lasts one billing period after the latest transaction date,
  plus one day. Monthly is 31 days and yearly is 366 days. An old, expired transaction from a restore
  never unlocks anything, and a transaction without a date grants nothing (fails closed).
- **Acknowledgement.** Every purchased or restored purchase is acknowledged on the device
  (`completePurchase`), because Google Play refunds a purchase that is not acknowledged within 3
  days. If the acknowledgement fails, it is retried at the next launch's restore.
- **Offline grace.** The existing 7-day offline grace (`EntitlementCache`) is unchanged. It records
  every new confirmation from the store or the family doc.
- **Sharing the plan with the family.** A parent phone writes the plan to the family doc
  (`familyPlanSharerProvider`). A paired child device never writes it. The written value is
  `plans.<app> = {plan, planExpiresAt (ISO-8601 string), inTrial: false, source: 'device', updatedBy, updatedAt}`.
  Child devices read it as before (`parseFamilyEntitlement`).
- **Accepted risk (owner, for zero cost).** This plan is *client-asserted*. A modified parent app, or
  a rooted phone that fakes its store answer, can give the family a paid tier. Only the rules below
  limit the damage. This is weaker anti-fraud than server receipts. It does not weaken child safety:
  a paid tier only adds features and children, and each child device still enforces its own lock
  locally.
- **Not available any more.** Without a server there is no check that one store subscription is used
  by only one family (`purchase_in_other_family`), and there are no RTDN renewals.
- **Follow-up.** StoreKit 2 is used when the `in_app_purchase_storekit` version that CI resolves uses
  it by default. Otherwise, call `InAppPurchaseStoreKitPlatform.enableStoreKit2()` once a direct
  dependency is added. The dependency was not added here, because there is no lockfile and pub could
  not be run in this environment.

## 2. AI assistant: hidden

The assistant is hidden from the Help screen and from the "AI assistant" row of the plan cards.
`AssistantService.ask` makes no network call while the flag is off, and the app contains no AI key.
The store listing texts no longer advertise it (`docs/marketing/STORE-LISTING.md`).

## 3. Parent alerts and "last seen" without push

`lib/services/family/family_events.dart`, `firestore_family_events.dart`, `presence_reporter.dart`,
`lib/features/parent/family_alerts.dart`

- **Child device events.** `notifyParent` (task submitted, adhan) adds one doc to
  `families/{f}/events/{auto}`: `{type, childId, at: serverTime, by: uid, detail?}`. The `detail`
  field holds only the task id or the prayer name.
- **Child device protection.** `reportProtection` keeps the current problems on
  `families/{f}/presence/{childId}.protection`. It adds one `protection` event with only the *new*
  reasons, and it writes nothing when nothing changed.
- **Child device "last seen".** A paired child device writes
  `presence/{childId}.lastSeen = serverTime` at start, on resume and every 15 minutes while open. It
  writes at most once per 15 minutes, and a paused Free child does not write.
- **Parent phone.** The parent phone lists the alerts of the last 7 days and "last seen" for each
  child device in the Parent area (Family alerts card). It shows a local notification for each new
  event while the app is open or resumed (up to 3 at once), and for a device that has been silent
  for over a day (once for each last-seen time). This replaces `checkHeartbeats`. Notification texts
  never contain the child's name.
- **Notification settings.** The parent's existing settings ("notify me about tasks / adhan") filter
  task and adhan notifications. Protection alerts always pass.
- **Retention.** On start, the parent phone deletes events that are older than 7 days.
- **Limit (accepted).** Without push, a parent sees alerts only when they open Zad X.

## 4. Referral rewards: hidden

The invite card and the friend-code field are hidden behind `FeatureFlags.referralRewards`.
`referralStatusProvider` returns a placeholder without making a call. The code is kept for a future
free design.

## Firestore rules needed (other engineer, `backend/firestore.rules`)

The helper names are the ones already in `backend/firestore.rules`.

```
// families/{familyId}: a PARENT member may write plans.<app> (client-asserted plan).
// Today `plans` is in serverOnlyFamilyKeys -> take it out of that list for updates and allow:
//   only isParent(familyId); only the key plans.play or plans.kids changes;
//   plan in ['basic','plus']; inTrial == false; source == 'device';
//   planExpiresAt is string && size() <= 40;  (ISO-8601; optionally also <= ~400 days ahead)
//   updatedBy == request.auth.uid; updatedAt == request.time.
// Keep 'plan', 'planApp', 'planExpiresAt', 'inTrial' (legacy top level), 'store', 'purchaseToken',
// referral keys server-only (nobody writes them on Spark).

match /families/{familyId}/events/{eventId} {
  allow read, delete: if isParent(familyId);
  allow create: if isMember(familyId)
    && request.resource.data.keys().hasOnly(['type', 'childId', 'at', 'by', 'detail', 'reasons'])
    && request.resource.data.type in ['task_submitted', 'adhan', 'protection']
    && validChildId(request.resource.data.childId)
    // a child device only for its own child; a parent device (one-device family) for any child
    && (isParent(familyId) || isChildDevice(familyId, request.resource.data.childId))
    && request.resource.data.at == request.time
    && request.resource.data.by == request.auth.uid
    && (!('detail' in request.resource.data) || (request.resource.data.detail is string && request.resource.data.detail.size() <= 64))
    && (!('reasons' in request.resource.data) || (request.resource.data.reasons is list && request.resource.data.reasons.size() <= 4
         && request.resource.data.reasons.hasOnly(['accessibility_off', 'device_admin_off', 'screen_time_off', 'clock_changed'])));
  allow update: if false;
}

match /families/{familyId}/presence/{childId} {
  allow read: if isParent(familyId) || isChildDevice(familyId, childId);
  allow create, update: if isChildDevice(familyId, childId)
    && request.resource.data.keys().hasOnly(['childId', 'lastSeen', 'platform', 'by', 'protection'])
    && request.resource.data.childId == childId
    && request.resource.data.lastSeen == request.time
    && request.resource.data.by == request.auth.uid
    && request.resource.data.platform is string && request.resource.data.platform.size() <= 16
    && (!('protection' in request.resource.data) || (request.resource.data.protection is list && request.resource.data.protection.size() <= 4
         && request.resource.data.protection.hasOnly(['accessibility_off', 'device_admin_off', 'screen_time_off', 'clock_changed'])));
  allow delete: if isParent(familyId);
}
```

**Indexes.** The parent query on events (`at > now-7d`, order by `at` desc, limit 50) and the prune
query (`at < now-7d`) each use the single field `at`, so they need no composite index.

**Quota (Spark).** Presence is at most 96 writes per child device per day. One event is written per
alert. The parent phone listens to 2 small collections.

## `cloud_functions` dependency

After this branch, `cloud_functions` is imported only by `lib/core/backend.dart`,
`lib/core/server_functions.dart` (the Blaze-only gateway) and the family-core files that the other
engineer is moving to rules. When that work lands, the only remaining user is the Blaze re-enable
path. The owner can then decide to drop the dependency together with that path. The dependency was
not removed here.
