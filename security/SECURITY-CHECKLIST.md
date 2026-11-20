# Zad X Play — Security & privacy release checklist

Tick every box before a store release. **[OWNER]** = Moatasem must do it personally (accounts,
money, legal signature). **[TEAM]** = engineering/security can do it. A release with any
unticked **Critical** line is blocked by the Quality Gate.

## 1. Children's privacy law (COPPA / GDPR-K / UK Children's Code)
- [ ] **[OWNER] Critical** Lawyer-reviewed privacy policy (AR + EN) published at a stable URL, linked in both stores and inside the app (Settings → Privacy). Must list: data collected (task progress, play minutes, city/prayer settings, FCM tokens, anonymous auth id, purchase tokens), purposes, processors (Google Firebase, Anthropic, Apple/Google stores), retention, parent rights, contact email.
- [ ] **[OWNER] Critical** Verifiable parental consent (COPPA) method chosen and implemented before any child data is synced to the cloud (e.g. parent sign-in + card/ID check via a VPC provider, or "email plus" if only internal use). Today the app uses anonymous auth only (risk R-27).
- [ ] **[TEAM] Critical** No child accounts, no child PII: child names/avatars from the multi-child work stay first-name/nickname only, optional, and are covered by the policy.
- [ ] **[TEAM] Critical** Data deletion: in-app "Delete family data" (parent-only) + web request form; backend `deleteFamily` Function (R-08). **[OWNER]** confirm retention periods.
- [ ] **[TEAM]** Data export for parents on request (GDPR access right) — manual process documented is acceptable for v1.
- [ ] **[OWNER]** Data Processing Agreements accepted: Google Cloud/Firebase DPA, Anthropic commercial terms (no training on API data) — keep copies.
- [ ] **[TEAM]** AI assistant only reachable behind the parent PIN; no child free-text chat (R-06).

## 2. Store kids' policies
- [ ] **[OWNER]** Google Play: Families policy self-check, target-audience declaration (parents, or Designed for Families if children are a target), Data safety form matching the privacy policy, Accessibility API Permissions Declaration + prominent disclosure, exact-alarm justification.
- [ ] **[OWNER]** Apple: Kids Category decision (guideline 1.3 — no third-party analytics/ads, parental gate before links/purchases), App Privacy "nutrition label", Family Controls **Distribution** entitlement approved.
- [ ] **[TEAM]** Parental gate (PIN) in front of purchases, external links, the AI assistant and settings.
- [ ] **[TEAM]** No ads SDKs, no third-party analytics in child-facing screens.

## 3. Firebase / Google Cloud
- [ ] **[TEAM] Critical** Deploy `backend/firestore.rules` from this branch; run rules emulator tests (to be added) before deploy.
- [ ] **[OWNER]+[TEAM] Critical** Firebase **App Check** enabled (Play Integrity on Android, App Attest on iOS, reCAPTCHA Enterprise on web) and enforced on Firestore + all callable Functions.
- [ ] **[OWNER] Critical** GCP **budget alerts** (e.g. 50/90/100 % of monthly budget) on the billing account, sent to the owner's email.
- [ ] **[TEAM]** Firestore TTL policies: `rateLimits.expiresAt` and `pairingCodes.expiresAt` (convert to a Timestamp field if needed).
- [ ] **[TEAM]** Set Function params at deploy: `PUBSUB_PUSH_SERVICE_ACCOUNT` (service account used by the Pub/Sub push subscription) and `PUBSUB_PUSH_AUDIENCE` (the audience configured on that subscription, usually the `playNotifications` URL). Without them the webhook rejects all requests (fail-closed).
- [ ] **[TEAM]** Pub/Sub push subscription for Play RTDN created **with authentication** (OIDC token, same service account/audience).
- [ ] **[TEAM]** Functions service account has only the roles it needs (Firestore user, Secret accessor for `ANTHROPIC_API_KEY`, FCM); Play Console API access limited to "View financial data / Manage orders and subscriptions".
- [ ] **[TEAM]** Cloud Logging: confirm no request bodies, questions, purchase tokens or device secrets are logged; set log retention.
- [ ] **[TEAM]** Verify per-IP rate limiting sees the real client IP in staging (R-18).

## 4. Anthropic (AI assistant)
- [ ] **[OWNER] Critical** Anthropic Console: set a **monthly spend limit** for the organisation/workspace and usage notification emails.
- [ ] **[OWNER]** Use a dedicated workspace + API key for Zad X production; never paste the key anywhere except `firebase functions:secrets:set ANTHROPIC_API_KEY`. Rotate if it ever appears in chat, email or git.
- [ ] **[TEAM]** Islamic Content Reviewer approves the system prompt and a sample set of answers (R-07).
- [ ] **[TEAM]** Red-team prompt set (jailbreaks, PII, scary content, religious rulings) run before each prompt change.

## 5. Purchases
- [ ] **[TEAM]** iOS server-side verification (App Store Server API) before iOS launch (R-10).
- [ ] **[TEAM]** Play: trial offer tagged `trial`; acknowledge purchases; test refund/revoke handling.
- [ ] **[TEAM]** Entitlement in the app read from the server-written family doc (R-16).

## 6. Devices
- [ ] **[TEAM]** Android release build: `allowBackup=false` present in merged manifest, R8/minify on, release signing key in Play App Signing (never in git).
- [ ] **[TEAM]** Android: alert the parent when the accessibility service is turned off (R-04).
- [ ] **[TEAM]** iOS: default to `.child` authorization (R-13).
- [ ] **[OWNER]** Windows: buy an Authenticode code-signing certificate; ship a signed MSI/MSIX (R-19).
- [ ] **[TEAM]** Windows: tell parents the child must use a Standard account (installer message exists).

## 7. Process
- [ ] **[TEAM]** `npm audit --audit-level=high` clean (CI) and `flutter pub outdated` reviewed.
- [ ] **[TEAM]** Secrets scan of the repo history (no keys, google-services files reviewed).
- [ ] **[TEAM]** Risk register: zero open Critical/High items, or each one signed off by the owner as accepted.
- [ ] **[OWNER]** Sign the legal/privacy review and the scholar review (see CLAUDE.md "prime condition").
