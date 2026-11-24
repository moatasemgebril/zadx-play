# Free plan = one child (paused, never deleted)

Owner decision 2026-11-21. Implemented on branch `feat/free-one-child`.

## Rule

* The Free plan covers **one child**. A family can have more children from the 7-day trial
  or an earlier subscription.
* On Free, the **free child** stays active. This is the child the parent chose (parent PIN asked
  again), otherwise the first child (oldest created, `child-1` for migrated families).
* Every other child is **paused**, never deleted. Wallet, tasks, adhkar progress, settings and
  the Firestore `children/{id}` docs and days are kept.
* Paused children become active again **by themselves** as soon as the plan includes
  `multipleChildren`: Basic, Plus, a store trial, or the on-device 7-day trial.
* Basic with more than 2 children, or Plus with more than 5, is out of scope here. Nothing
  is paused in that case (open question for the owner).

## Where it is enforced

| Place | Behaviour |
|---|---|
| Parent / shared device (`childPauseProvider`) | Paused children are greyed with "Paused: subscribe to resume". They cannot be selected and are never the active child. They cannot be picked for pairing. "Choose which child stays active" is PIN-protected. |
| Paired child device (`thisDevicePausedProvider`) | Reads the family's server-written plan fields (`plan`, `planExpiresAt`, `createdAt`, `freeChildId`), cached on the device. If its child is paused, it shows a kid-safe "ask a parent" screen with no price; plan details sit behind the parent PIN. The device is **not locked**: the policy is `locked: false` with reason `paused`, and adhan alarms are cleared. It is **not monitored**: no tamper reports. If the status is unknown, the child is treated as not paused, so the device stays locked. |
| Backend (`childPaused` in `security.ts`) | `notifyParent` sends no push for a paused child. `createPairingCode` and `redeemPairingCode` refuse with `child_paused` (the code is not used up, so it still works if the parent subscribes within its 10 minutes). `reportProtection` sends no alert and deletes the heartbeat. `checkHeartbeats` sends no "device silent" alert. `reportUsage` ignores the minutes. `devicePolicy` returns `paused`; the Windows guard is unlocked on Free anyway. |
| `setFreeChild` (new callable) | Parent devices only, rate-limited. Writes `families/{id}.freeChildId`, which is a server-only key in `firestore.rules`, so a child device cannot choose itself. The app calls it only when the free child differs from what the server has (default `child-1`). |

The server can't see the on-device trial, so it counts its own 7-day trial from the family's
`createdAt`. Nobody is paused during that time. `firestore.rules` now requires
`createdAt == request.time` on create, so a client cannot extend this trial. This trial only
ever lifts the pause. It costs nothing because no paid API is involved.

## Child-safety note (for the Quality Gate and the owner)

A paused child's phone is **not locked** (owner: "not locked/monitored as separate children").
The parent sees this in the dashboard: "A paused child's device isn't locked or monitored."
If the owner prefers paused devices to stay locked at prayer times (the Free lock), only
`lockPolicyProvider` / `pausedLockPolicy` and the adhan alarm scheduling need to change.

## Assistant during the on-device trial (Quality Gate item 2)

`askAssistant` allows only store-verified plans and returns `subscription_required` during
the on-device trial. **Choice: the client follows the server.** `assistantAvailable()` needs a
verified plan (not `Entitlement.deviceTrial`). During the device trial, the Help screen says
"The Zad X assistant is available after subscribing to Basic or Plus" (no price). We did not
open the assistant on the server for `createdAt`-based trials. Anonymous sign-in makes new
families free to create, and every new family would get paid Claude API calls, which is a
cost-abuse risk.

## Parent PIN in onboarding (Quality Gate item 1)

`FirstRunGate` (in `MaterialApp.router(builder:)`) shows only the "For parents" PIN step until
a PIN exists. The step asks for the PIN twice (4 to 6 digits) and an "I'm the parent or
guardian" checkbox. Child mode is not reachable before that. `ParentGate` no longer creates a
PIN. If none exists, it shows a "for parents" card that opens the onboarding PIN step.
