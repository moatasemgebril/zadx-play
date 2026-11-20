# Parent push notifications

Owner request: BACKLOG item 1 ("فعّل نظام push"). Branch `feat/push-notifications`.

## Decision (orchestrator / product / CTO)

- Server push is **parent-facing only**. Nothing is ever sent to a paired child device.
- Prayer (adhan) reminders on the child's device **stay local**
  (`lib/services/notifications/prayer_notification_service.dart`), with no server involved.
- **No marketing push**, to anyone. There are no promo, upsell or "come back" messages.
- Payloads contain **generic fixed text + opaque ids only** (no child nickname, no task
  title, no free text from the client). The parent app loads details after it is opened,
  behind the parent PIN.
- Off by default. Each parent device opts in separately from the parent area.

## Push types

| Type | Sent when | Who triggers | Respects family switch |
|---|---|---|---|
| `task_submitted` | Child marks a task done (waits for approval) | child/family device → `notifyParent` | `notifyOnTasks` |
| `unlock_request` | Child taps "I prayed" during the prayer lock | child/family device → `notifyParent` | `notifyOnTasks` |
| `adhan` | Prayer lock starts (console reminder for parents) | family device → `notifyParent` | `notifyOnAdhan` |
| `device_paired` | A phone or Windows PC joins the family (security event) | server (`redeemPairingCode`) | always (device opt-in) |
| `weekly_summary` | Saturday 09:00 UTC, "summary ready", no numbers | server (`weeklySummary`, scheduled) | always (device opt-in) |

## User stories and acceptance criteria

**US-1 Task approval alert.** As a parent, I want a notification when my child finishes a
task, so that I can approve it quickly.
- AC1 Given push is on for my phone, when my child taps "Done", I get one notification
  "A task is waiting for your approval" (or the Arabic text, matching my app language).
- AC2 The notification shows no child name and no task title; `data` holds only `type`,
  `childId` and `taskId` (ids).
- AC3 Tapping it opens the parent area, which still asks for the PIN.
- AC4 If "Notify me when tasks are done" is off, nothing is sent.
- AC5 The device where the child tapped "Done" does not notify itself.

**US-2 Unlock request.** As a parent, I want to know when my child asks to unlock games after
praying, so that games are not locked longer than needed.
- AC1 "I prayed" during a prayer lock sends `unlock_request`, otherwise `task_submitted`.
- AC2 At most 10 unlock pushes per family per hour, so tapping repeatedly cannot spam parents.

**US-3 Security event.** As a parent, I want to be told when a device is linked to my
family, so that I notice a pairing I did not make.
- AC1 After a phone or Windows PC redeems a pairing code, all opted-in parent devices get
  "A new device was linked to your family…", with `target` = `phone` | `windows`.
- AC2 The newly linked device is not notified, and a phone that becomes a child device has its
  own parent token deleted.
- AC3 A failed push never makes the pairing fail.

**US-4 Weekly summary.** As a parent, I want a weekly reminder to look at progress.
- AC1 At most one per family every 6 days, with no numbers or names in the payload.

**US-5 Control and consent.** As a parent, I decide whether this phone gets notifications.
- AC1 The toggle is hidden on child devices, desktop/web, and builds without Firebase.
- AC2 Turning it on first shows an in-app explanation, then the OS permission prompt.
  "Not now" does nothing. If the OS permission is denied, the card explains how to enable it in Settings.
- AC3 Turning it off deletes `parentDevices/{uid}` and the FCM token.
- AC4 Without `google-services.json` / `GoogleService-Info.plist` (CI), the app starts
  normally and push stays unavailable.

**US-6 Child safety (non-functional).**
- Child devices can never read or write any push token (Firestore rules).
- Recipients are re-checked on every send: must still be a member and not in
  `childDevices`.
- Invalid or expired tokens are deleted automatically.

## Data flow

```
Child phone ── notifyParent(familyId, childId, type, {taskId|prayer}) ──► Cloud Function
                                                                          │ auth + member + child access
                                                                          │ per-uid limit (30/h)
                                                                          │ family switch (notifyOnTasks / notifyOnAdhan)
                                                                          │ per family+type limit
                                                                          ▼
                                     families/{id}/parentDevices/*  (admin SDK read)
                                                                          │ selectRecipients: member, not child device,
                                                                          │ valid token, not the caller, max 10
                                                                          ▼
                                     FCM sendEachForMulticast (AR group, EN group)
                                       notification: generic text   data: type + ids
                                                                          │ token-not-registered / invalid → delete doc
                                                                          ▼
Parent phone (opted in) ── tap ──► app opens /parent (PIN gate) ──► reads details from Firestore
```

Code:
- Backend: `backend/functions/src/push.ts` (pure helpers, tested) and
  `backend/functions/src/index.ts` (`sendToParents`, `notifyParent`, `weeklySummary`,
  `notifyPaired` in `redeemPairingCode`).
- Rules: `backend/firestore.rules`, `match /parentDevices/{deviceUid}`.
- App: `lib/services/notifications/push_service.dart` (`pushControllerProvider`),
  `push_payload.dart` (pure, tested in `test/push_payload_test.dart`),
  `lib/features/parent/push_settings_card.dart`.

## Data model

```
families/{familyId}/parentDevices/{uid}
  token:     string   FCM registration token (20–4096 chars, [A-Za-z0-9_:.-])
  platform:  'android' | 'ios'
  lang:      'ar' | 'en'
  updatedAt: server timestamp
```
Rules allow read, write and delete only when `request.auth.uid == uid` and the caller is a parent member
(a member that is not in `childDevices`). Any other key is rejected.
The old `families/{id}.parentTokens` array (readable by every member, including child devices)
is now server-only and is deleted by the server the next time it sends a push to that family.

## Privacy notes (for the privacy policy and store data-safety forms)

- **Data collected:** one FCM token per parent device that opts in, plus the app language.
  No child data is collected for push.
- **Purpose:** to deliver parent alerts only. It is not used for advertising, analytics or profiling.
- **Content:** fixed generic text. Payloads never include a child's nickname, avatar, task
  titles, location or free text. Ids are random or opaque.
- **Children:** child devices never register tokens and never receive server push
  (COPPA / GDPR-K data minimisation).
- **Retention:** a token is deleted when the parent turns push off, when FCM reports it as invalid,
  or when the device is re-paired as a child device. A Firestore TTL on `rateLimits.expiresAt` keeps
  rate-limit counters short-lived (keys are hashed).
- **Processors:** Google Firebase Cloud Messaging, and Apple Push Notification service on iOS.
- Store forms: Play Data safety, "Device or other IDs" (FCM token), app functionality, not shared.
  Apple privacy label: "Device ID", app functionality, not linked to identity for tracking.

## Deploy order (engineering)

1. Deploy functions + rules first (`cd backend && firebase deploy --only functions,firestore:rules`).
   An older backend rejects `unlock_request` (the call fails and that push is lost).
2. Then ship the app build.
3. Unfiltered collection-group reads of `parentDevices` (weekly job) need no composite index.
   If the deploy reports a missing index, accept the console link.

---

## OWNER-ONLY steps (paste-ready; the team must not do these)

These steps need the owner's Google, Apple and GitHub accounts. **Never commit any of these files or keys.**

### 1. Create or confirm the Firebase project
1. Open https://console.firebase.google.com → select the Zad X project, or **Add project**
   (name: `zadx-play`, Analytics **off**: not needed for a kids' app).
2. **Build → Authentication → Sign-in method → Anonymous → Enable**, if not already enabled.
3. **Build → Firestore Database**: it should already exist in region `europe-west1` (or eur3).
4. **Project settings → Cloud Messaging**: confirm *Firebase Cloud Messaging API (V1)* shows
   **Enabled**. The legacy API is not needed.
5. **Upgrade to Blaze** (pay-as-you-go) if not already done: Cloud Functions and the
   scheduled `weeklySummary` job require it. Set a budget alert (Billing → Budgets, e.g. $10).

### 2. Upload the APNs auth key (iOS)
1. https://developer.apple.com/account → **Certificates, IDs & Profiles → Keys → +**.
2. Name: `ZadX APNs`, tick **Apple Push Notifications service (APNs)** → Continue → Register.
3. **Download** the `.p8` file (one download only, so store it in your password manager).
   Note the **Key ID**, and your **Team ID** (top right of the developer page).
4. **Identifiers → com.zadx.app → Capabilities → Push Notifications → enable → Save**.
   Then regenerate/download the provisioning profiles (Xcode automatic signing does this).
5. Firebase console → **Project settings → Cloud Messaging → Apple app configuration →
   APNs Authentication Key → Upload**: choose the `.p8` file, then enter the Key ID and Team ID.
6. In Xcode (on your Mac): Runner target → **Signing & Capabilities → + Capability →
   Push Notifications**, and **+ Background Modes → Remote notifications**. This adds
   `aps-environment` to `ios/Runner/Runner.entitlements` and `UIBackgroundModes` to Info.plist.
   Commit those two file changes, which contain no secrets.

### 3. Add the app config files (locally, never committed)
```bash
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=<your-project-id> --platforms=android,ios
```
This writes `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`.
Both are already in `.gitignore`.

### 4. Deploy the backend
```bash
cd backend
firebase use <your-project-id>
cd functions && npm install && npm run build && cd ..
firebase deploy --only functions,firestore:rules
```
Then enable a TTL policy: Firestore → **TTL → Create policy** → collection group
`rateLimits`, field `expiresAt`.

### 5. GitHub secrets (optional)
CI builds **without** Firebase and push stays off, so no secret is required.
Only if you later want CI to build a Firebase-enabled APK or IPA, add these under Settings →
Secrets and variables → Actions:
- `GOOGLE_SERVICES_JSON_B64`: `base64 -w0 android/app/google-services.json`
- `GOOGLE_SERVICE_INFO_PLIST_B64`: `base64 -i ios/Runner/GoogleService-Info.plist`

Never upload the APNs `.p8` key to GitHub. It belongs in Firebase only.

### 6. Smoke test (after steps 1–4)
1. Install on a parent phone → Parent area → **Parent notifications** → On → Allow.
2. Pair a child phone, then mark a task done on it. The parent phone should get
   "A task is waiting for your approval" within seconds.
3. Turn the toggle off. In the Firebase console, `families/<id>/parentDevices/<uid>` should be gone.
