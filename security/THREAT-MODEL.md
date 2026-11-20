# Zad X Play — Threat model (STRIDE)

Version 1 · 2026-11-20 · branch `sec/hardening-1` · author: ZADX security team (CISO / AppSec / cloud).
Re-review on every change to `backend/`, pairing, purchases, the AI proxy or the native lock code.

## 1. System in one picture

```
 Parent phone (Flutter) ─┐                      ┌─ Cloud Functions (europe-west1)
 Child phone (Flutter) ──┼─ Firebase Auth ──────┤   askAssistant ─────────► Anthropic API (secret key)
   + Android a11y lock   │  (anonymous today)   │   verifyPurchase ───────► Google Play Developer API
   + iOS Screen Time     │                      │   playNotifications ◄── Pub/Sub push (Play RTDN)
 Web dashboard ──────────┘   Firestore (rules)  │   create/redeemPairingCode
                                                 │   notifyParent ─────────► FCM
 Windows PC: Zad X Guard ── device secret ──────┘   devicePolicy / reportUsage (HTTP)
```

Trust boundaries: (1) device ⇄ Firebase (client is untrusted, incl. a curious child);
(2) Cloud Functions ⇄ third parties (Anthropic, Google Play, FCM); (3) the child's own device —
the child has physical access, so anything enforced only on-device is "best effort";
(4) Windows Standard user ⇄ SYSTEM service.

Actors: parent (owner of the family), child (wants more play time; may tap anything, may borrow a
parent's phone), other families' users, anonymous internet attackers, a malicious/compromised
paired device, store/webhook impostors.

## 2. Assets

| # | Asset | Where | Why it matters |
|---|---|---|---|
| A1 | Child data (task progress, play minutes, prayer status; soon child names/avatars) | Firestore `families/*/children/**`, device prefs | COPPA / GDPR-K personal data of a minor |
| A2 | Parent account / family membership | Firebase Auth (anonymous), `families.members` | whoever is a member reads and writes the child's data |
| A3 | Pairing secrets (6-digit codes, Windows device secret) | `pairingCodes`, `families/*/devices`, `%ProgramData%\ZadX\device.dat` | a stolen code = joining someone's family |
| A4 | Anthropic API key and spend | Functions secret `ANTHROPIC_API_KEY` | key theft or abuse = unbounded bill; unsafe output reaching a child |
| A5 | Purchases / receipts / entitlement | `families.plan*`, `purchaseToken`, referral fields | revenue; free Plus; referral fraud |
| A6 | The game lock (policy + enforcement) | Firestore days doc, Android `LockStore`, iOS `SharedStore`, Windows Guard | the product promise to parents |
| A7 | Parent PIN | device SharedPreferences (hash) | gate to approvals and settings on a shared device |

## 3. STRIDE by component

Status legend: **Fixed** (this branch) · **Open** (see risk register id) · **Accepted**.

### 3.1 Firestore + security rules
| STRIDE | Threat | Status |
|---|---|---|
| S | Any signed-in user reads another family | Mitigated by `members` check on read (already) |
| T | Client creates a family with `plan: "plus"` → free paid features | **Fixed** (create rule forbids server-only keys) |
| T | Member adds arbitrary uids to `members` (persistence, sharing) | **Fixed** (`members` server-only) |
| T | Malformed days doc breaks lock maths on other devices | **Fixed** (type/range validation) |
| T | Paired child device (also a "member") approves its own tasks / edits settings by calling Firestore directly | **Open R-03** — no parent/child roles yet |
| I | Child data readable by every member device | Accepted by design (single family) |
| D | Unbounded writes / doc growth | Partially: day doc size bounded; settings not bounded (R-15) |
| E | Deleting the family / data deletion | No client delete; no deletion function yet (**Open R-08**) |

### 3.2 Cloud Functions
| STRIDE | Threat | Status |
|---|---|---|
| S | Brute-forcing 6-digit pairing codes to join a family (anonymous accounts are free) | **Fixed** (IP + uid + global rate limits, transactional single use). Residual: **R-02** (no parent confirmation) |
| S | Forged Play RTDN webhook credits referrals | **Fixed** (Pub/Sub OIDC + Play API re-check). Owner must set params (checklist) |
| S | Windows device secret guessed / compared non-constant-time | 256-bit secret + SHA-256 + constant-time compare (fixed helper) |
| T | Client claims Plus with a Basic receipt (productId from client) | **Fixed** (tier from Google lineItems) |
| T | One receipt shared across many families | **Fixed** (token bound to one family) |
| T | iOS purchases not verified | Function refuses iOS (`unimplemented`) — **Open R-10** |
| R | No audit trail of approvals / purchases | **Open R-14** |
| I | Error strings / logs leak internal ids or purchase tokens | **Fixed** (generic HTTP errors, token-free logging) |
| D | AI proxy abuse runs up the Anthropic bill | **Fixed** (subscription required, per-family daily cap incl. Plus, per-user burst limit, max_tokens 500, timeout). Residual R-05 (no App Check, no hard Anthropic cap until owner sets it) |
| D | Push-notification spam to parents | **Fixed** (type allowlist, 30/h per user) |
| E | Path injection through ids used in Firestore paths | **Fixed** (`isSafeId` on familyId/childId/deviceId/referrerId) |

### 3.3 AI assistant content (child audience)
| Threat | Status |
|---|---|
| Child (or prompt injection) gets unsafe / adult / frightening content | Partially fixed: kid-safe rules in system prompt; **Open R-06** (no output moderation / logging-free review) |
| Model invents Quran/hadith text or rulings | Prompt forbids quoting from memory; **Open R-07** (Islamic Content Reviewer must review prompt and sample answers) |
| PII sent to Anthropic | Prompt tells model not to ask; user may still type PII (R-06). No PII is logged by our function |

### 3.4 Parent PIN
| Threat | Status |
|---|---|
| Child guesses PIN by trying repeatedly | **Fixed** (5 free tries, then 30 s → 15 min, persisted) |
| Offline cracking of unsalted SHA-256 from a backup / rooted device | **Fixed** (PBKDF2 20k + salt; `allowBackup=false`). Residual: 4–6 digit PINs stay crackable on a rooted device (Accepted, R-12) |
| Child sets the PIN first on a fresh install | **Open R-11** (onboarding should force parent PIN creation) |
| Clock moved forward to skip lock-out | Accepted (R-12) |

### 3.5 Android lock
| Threat | Status |
|---|---|
| Notification shade / keyboard stops the play-minute counter (free play) | **Fixed** |
| Game kept running in split-screen beside the shield | **Fixed** (go Home before shield) |
| Exported components | Checked: service/activity/receivers `exported=false`; a11y service protected by `BIND_ACCESSIBILITY_SERVICE` |
| Accessibility scope | Checked: window-state events only, `canRetrieveWindowContent=false` (minimal) |
| Child disables the accessibility service, force-stops or uninstalls the app, or changes the clock | **Open R-04** (detect + alert parent; consider Device Admin / Family Link guidance) |
| Restore old prefs from backup | **Fixed** (`allowBackup=false`) |
| Lock state in plain SharedPreferences (rooted device) | Accepted |

### 3.6 iOS lock
| Threat | Status |
|---|---|
| Entitlements | Checked: only `family-controls` + app group `group.com.zadx.app`; no extra entitlements |
| Child removes Screen Time authorization (`.individual` mode) | **Open R-13** — prefer `.child` authorization via Family Sharing (removal then needs parent) |

### 3.7 Windows Guard
| Threat | Status |
|---|---|
| Child pre-creates `%ProgramData%\ZadX` to own/replace `device.dat` | **Fixed** (fresh folder, Administrators owner, SID-based ACL) |
| Device secret at rest | DPAPI (LocalMachine) + entropy + folder ACL (SYSTEM/Admins). Note: LocalMachine DPAPI is only as strong as the ACL |
| Secret sent over plain HTTP by misconfiguration | **Fixed** (https enforced) |
| Child renames/copies a game exe (process-name matching) | **Open R-09** |
| Child is a Windows administrator | Accepted / documented (must be Standard) |
| Unsigned installer / binary tampering | **Open** (code-signing in checklist) |

## 4. Out of scope for this pass (recorded, not edited)
Games, edu-games, audio, wallet, children and parent screens belong to other teams; their issues
are in `RISK-REGISTER.md` (R-03, R-11, R-16).
