# Zero-cost backend: family core without Cloud Functions

Owner decision 2026-11-28: zero technical cost forever. Firebase stays on the free **Spark** plan:
Anonymous Auth, Firestore and Hosting. No Cloud Functions, no Secret Manager, no card.

Phase 1 (this document) moves the **family core** from callables to plain client writes that
`backend/firestore.rules` enforces. The same security properties hold: the rules decide, the app
only proposes. Order of priority: child safety and privacy > Islamic accuracy > security.

Files: `backend/firestore.rules` · `lib/services/family/pairing_code.dart`,
`pairing_service.dart`, `family_core_logic.dart`, `firestore_family_repository.dart`,
`device_removal.dart` · tests `backend/functions/test/rules.test.js` (Firestore emulator, CI job
`backend`), `test/family_core_logic_test.dart` (flutter test).

## What moved where

| Callable (needs Blaze) | Now (Spark) | Enforced by |
| --- | --- | --- |
| `createPairingCode` | Parent device writes `pairingCodes/{sha256(code)}` | `pairingCodeCreateOk` |
| `redeemPairingCode` (phone, parent phone) | One transaction: read code, add **itself** to the family, delete the code | `joinOk` + code `delete` rule |
| `redeemPairingCode` (Windows) | Guard creates `families/{f}/devices/{its uid}` + deletes the code (rules ready; guard client is Phase 2) | `windowsJoinOk` |
| `removeLinkedDevice` | One transaction: family update + `removedDevices/{uid}` + `audit/{id}` | `removeOk`, `removedNow`, `auditEntryOk` |
| `checkDeviceMembership` | Two server reads: family doc, then own `removedDevices/{uid}` | `get` rules |
| `approveTask` | Parent transaction on the day doc (one task, bounded minutes) | `parentApprovalOk` |
| `rejectTask` | Plain parent write (`progress.{task} = todo`) | existing parent day rule |
| `setFreeChild` | Parent writes `families/{f}.freeChildId` | `freeChildOk` |
| Device-removal audit | Client-written by the removing parent, append-only | `auditEntryOk`, no read/update/delete |

The old functions stay in `backend/functions` (optional, needs Blaze); the app no longer calls
them. Out of scope here (owned elsewhere): `verifyPurchase`, `askAssistant`, `notifyParent`,
`reportProtection`, `referralStatus`, the Windows guard HTTP API, `lib/core/feature_flags.dart`.

## Data model

```
families/{familyId}
  members: [uid]                    every linked device (each its own anonymous uid)
  childDevices: {uid: childId}      child devices; any other member is a parent device
  parentDevices: {uid: linkedAt}    phones linked with a parent code
  memberOp: {op: 'join', uid, code, at}            last join (code = code doc id)
          | {op: 'remove', uid, by, at, audit}     last removal (audit = audit doc id)
  freeChildId                       Free plan: the child that stays active
  removedDevices/{uid}  {removedAt}                removal marker, `get` by that uid only
  audit/{autoId}        {action:'device_removed', byUid, targetUid, targetRole, at, expiresAt}
  devices/{guardUid}    {type:'windows', childId, name, code, createdAt}
  children/{childId}/days/{yyyy-MM-dd}
    approved {taskId: minutes}, earnedMinutes, requiredDone   credits (approval write only)
    approval {taskId, by, at}                                 the last approval (rules bookkeeping)
pairingCodes/{sha256("zadx-pair-v1:" + code)}
  {familyId, target: 'phone'|'parent'|'windows', childId?, createdBy, createdAt}
```

No new personal data: uids, child ids, times. Children still have no accounts and no PII
(nickname + built-in avatar only, unchanged).

`memberOp` is how one rule sees the other writes of the same commit: the family-doc rule reads
the code named in `memberOp.code` with `get()` (state before) and checks it is gone with
`existsAfter()`; the code, marker and audit rules read `memberOp` with `getAfter()`. Every op must
carry `at == request.time`, so an old `memberOp` can never be replayed.

## Rules, per flow

### Pairing codes
- **Code:** 10 symbols from `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (31 symbols, no 0/O/1/I/L),
  `Random.secure()`, shown as `XXXXX-XXXXX`. Input is case-insensitive; dashes, spaces and
  Arabic-Indic digits are accepted. The code itself is never stored; the doc id is its SHA-256.
- **Create** (`pairingCodeCreateOk`): only a parent device of `familyId` (member, not in
  `childDevices`); `createdBy == auth.uid`; `createdAt == request.time`; fixed keys; `phone` /
  `windows` need an existing child doc, `parent` has no child. Never updated. A phone keeps one
  live code: the next code withdraws the previous one (creator may delete its own code).
- **Read**: `get` by id only, signed in, only while live (`request.time < createdAt + 10 min`).
  `list` is denied. A missing, used or expired code is the same permission-denied.
- **Join** (`joinOk`): the redeemer is not yet a member; `members` gets exactly its uid appended;
  `phone` code → `childDevices[uid] == code.childId`, nothing in `parentDevices`; `parent` code →
  `parentDevices[uid] == request.time`, nothing in `childDevices`; no other family field changes;
  the code is live, belongs to this family, its creator is **still a parent device**; and the
  code doc is deleted in the same commit (single use, two racing redeemers cannot both win).
- **Windows**: `devices/{auth.uid}` with the code's child, code deleted in the same commit. The
  guard reads only its own doc and is not a family member.
- A parent phone that joins another family deletes its own untouched fresh family (rule: sole
  member, only `members/createdAt/settings`). As before, a phone whose family already has children
  is refused (`parent_link_family_in_use`) so its data is not stranded.

### Device removal and the removed-device check
- `removeOk`: caller is a parent device; `memberOp = {op:'remove', uid:X, by:caller, at:now,
  audit:id}`; X was a member; `members == old.removeAll([X])`; only X leaves `childDevices` /
  `parentDevices`; **at least one parent device remains** (so never the last parent, including
  removing yourself); `audit/{id}` and `removedDevices/X` exist after the commit.
- `removedDevices/{uid}`: written only in that commit (`removedNow`), `{removedAt}` only; `get`
  only by that uid; never listed or deleted from a client.
- `audit/{id}`: created only in that commit by the removing parent, role checked against the
  family doc before the removal; no client read, update or delete (append-only). Optional TTL
  policy on `expiresAt` (about one year, set from the parent's clock: retention only).
- **Check** (`FirestoreFamilyRepository.probe`), both reads with `Source.server`:
  1. family doc readable and lists my uid → member;
  2. family doc refused (permission-denied) and my marker exists → **not a member**;
  3. anything else (offline, timeout, no marker, deleted family) → unknown.
  `RemovalDetector` still needs two explicit "not a member" answers in a row, so offline or a
  rules mistake never resets a child device (it stays locked, as before).
- Not possible without a server: revoking the removed device's refresh token. Not needed for
  Firestore (access is by uid membership), but the uid itself stays valid.

### Task approval
- `parentApprovalOk`: only a parent device; one task per write named in `approval.taskId`
  (`by == auth.uid`, `at == request.time`); only that key of `approved` may appear; credit is an
  int 0..120; a task already approved keeps its credit; `earnedMinutes == old + credit` (0 when
  already approved) and at most 600 when it grows; `requiredDone` is a bool (the parent's app
  computes it from the required list, as the function did with the parent's list); the prayer lock
  may only be ended (`prayerLock = false`, `prayerLockAt` / `prayerLockSinceMs` only deleted).
- Child devices: unchanged rules; `approval`, `approved`, `earnedMinutes`, `requiredDone` are not
  in `childDayKeys`, so a child device can never credit itself (even with the parent PIN).
- `rejectTask` is the normal parent day write (`progress.{task} = todo`; credits stay).
- The approval runs in a transaction (fails fast offline → queued by `ApprovalQueue` as before).

### Free child
- `freeChildOk`: parent device, only `freeChildId` changes, valid id, `child-1` or an existing
  child doc. Child devices cannot pick themselves.

## Threat notes: no server rate limit

Callables had per-IP / per-uid / global rate limits. Spark has none, so:

1. **Guessing a code.** 31^10 ≈ 8.2 × 10^14 (≈ 49.5 bits). A guess is one `get`. Even an attacker
   with 10 000 live codes in the whole app and the **entire** Spark daily read quota (50 000 reads)
   has about 10 000 × 50 000 / 8.2 × 10^14 ≈ 6 × 10^-7 chance per day. Codes live 10 minutes
   (server time), are single use, cannot be listed, and missing / expired / used look the same.
2. **What a winner gets.** Only the role the code grants, in one family; the parent sees every
   linked device (Parent → Link devices) and can remove it at once. The creator must still be a
   parent device, so a removed phone's codes die with it.
3. **Who can create codes.** Only parent devices of that family. An attacker's own codes only open
   the attacker's own family.
4. **Quota exhaustion (DoS).** Anyone with an anonymous uid can spend the project's free reads
   (denied reads count too). This is a Spark-wide risk, not specific to pairing. Mitigation:
   Firebase **App Check** (free with Play Integrity / App Attest / reCAPTCHA Enterprise free
   tier) with enforcement on Firestore before launch; budget alerts need no card.
5. **Modified app.** Every invariant above is in the rules, not in the app; the app's own checks
   (`family_core_logic.dart`) only give friendly errors.
6. **Anonymous uids are free.** Rules never trust a uid count; they trust membership and roles.

Accepted weaker properties (vs. Functions): no token revocation on removal; no server check that
a phone code's child is paused on Free (the parent app does not offer paused children, and the
child device applies the pause from the family plan itself); the audit's `expiresAt` uses the
parent's clock; expired unused codes stay until withdrawn (tiny, no personal data).

## Testing

- `backend/functions/test/rules.test.js` (emulator): create/read/join/reuse/expiry of codes,
  parent codes, Windows registration, removal (marker, audit, last parent, forging), free child,
  approval bounds and the daily cap, child self-credit attempts, fresh-family deletion.
  Run: `cd backend/functions && npm run test:rules:deps && npm run test:rules` (Java + firebase-tools).
- `test/family_core_logic_test.dart`: code format and hashing, approval math, removal decision,
  membership answer.

## Phase 2 (not done here)

- **Windows guard API** (`devicePolicy` / `reportUsage`): the guard signs in anonymously, registers
  with a windows code (rules above are ready), then reads its child's day / family settings and
  adds used minutes through Firestore rules for `devices/{uid}`; parent listing and revocation of
  guards (BACKLOG P1-3b).
- **Heartbeats** (`checkHeartbeats`, scheduled): child devices write a last-seen field; the parent
  app checks it when it opens and shows "device stopped reporting".
- **Store notifications** (`playNotifications`, `appStoreNotifications`, `verifyPurchase`): on-device
  Play Billing / StoreKit 2 entitlement with the cached plan; no client-written plan trusted for
  other devices without a parent-device re-check.
- **notifyParent / reportProtection**: no FCM sends without a server; in-app status on the parent
  device instead.
- **App Check** enforcement on Firestore before launch.
