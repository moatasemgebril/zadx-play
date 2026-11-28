# ZADX Backlog

The orchestrator reads this file at the start of every cycle (see CLAUDE.md).
Owner requests come first within the priority order. Close an item by moving it
to "Done" with the PR link; record decisions in the ZADX LOG.

## Owner requests — 2026-11-27

- [x] **New brand artwork ("ZX")** — branch `design/zx-brand-refresh`. Owner decisions (asked one by one):
  1. App icon on every device = the "ZX" artwork, for **both** Zad X Play and Zad X Kids (Android adaptive
     icon, iOS, web, Windows, macOS, Google Play 512 icon).
  2. Logo inside Zad X Play = "ZX ZAD X" (`BrandLogo`); the splash shows "ZX" + the "Zad X" wordmark.
     Kids keeps its drawn "ZAD X KIDS" wordmark inside the app.
  3. Brand navy backdrop (code-drawn, no image) for the **splash and the parent area** (parent, settings,
     help, subscription) only. Child screens (home, games, tasks, Quran) keep their bright scenes.
  4. Google Play Console account opened by the owner with `zadxsupport@gmail.com`.
  Tooling: `tools/gen_brand_assets.py`. Store art: `docs/store/assets/` (feature graphic: owner picks a/b/c/d).
- [ ] Device check of the new icon (Pixel circle mask, Samsung squircle) and of the navy parent area.
- [ ] Optional: Android 13 themed (monochrome) icon layer.

## Owner requests — 2026-11-24

- [x] **PlayStation lock steps in the app** (owner: people should see them): `PsLockSteps` (lib/features/parent/ps_lock_steps.dart) in the parent Consoles card, shown on every plan, 7 steps AR/EN, neutral words (same in Kids). Test: `test/ps_lock_steps_test.dart`.
- [ ] **Google Play submission** — full guide in `docs/store/GOOGLE-PLAY-SUBMISSION.md`; the owner opens the account and pays the $25 himself. Team follow-ups: (1) signed release AAB in CI with an upload key from GitHub Secrets (off until the secret exists); (2) privacy policy + terms on a stable URL; (3) screenshots, 1024×500 feature graphic, 512 icon; (4) Accessibility review video; (5) friends/testers via Play internal testing (replaces sending the APK by hand).
- [ ] **Regional pricing abuse** (owner question): price follows the store account country (Play: country change once a year + local payment method; Apple: local payment method), not IP/VPN. Rules: never sell on the web with IP-based prices; keep the cheapest market within a sensible gap; log the store country per purchase on the server.
- [ ] **Client/server pause rule mismatch** (P2): the server treats a Play OR Kids plan as paid for pausing children; the app checks only its own plan. Align the app with the server (team recommendation, owner did not object 2026-11-24).

## Owner requests — 2026-11-23

- [x] **Game-feel sounds** (owner: page sound like in games, a "row cleared" style win sound, a coin/point sound). → **Done in branch `feat/game-sfx`, pending CI + Quality Gate** (2026-11-23): original sounds from `tools/gen_sfx.py` (`transition.wav` whoosh + chime, `win_combo.wav`, `coin*.wav` with 4 pitch variants; nothing copied from other games, see `assets/sfx/LICENSE.txt`). Page sound on child route changes, debounced 350 ms, silent into the parent area/settings/subscription/Quran tab; win combo on game round won (replaces levelUp there); coin pings per earned star and when a parent approval adds minutes (replaces star there). All effects still silent during adhan/Quran and follow mute + volume. Tests: `test/sfx_rules_test.dart`, `test/edu_game_hooks_test.dart`. Needs an ear check on a real phone (volume balance).

## Owner requests — 2026-11-20 (the team decides and solves these itself)

The owner asked that the team handle these open questions on its own. Make
sensible decisions, log them in the ZADX LOG, and only list for the owner the
steps that truly need his accounts, signature or money.

### 1. Push notifications system ("فعّل نظام push")
- Today the app only schedules local adhan notifications
  (lib/services/notifications/prayer_notification_service.dart). There is no
  server push (no firebase_messaging, no APNs).
- Product manager + CTO: decide what push is for. Suggested, child-safe scope:
  parent-facing alerts (child finished tasks, unlock requests, pairing/security
  events, weekly summary); prayer reminders stay local. No marketing push to
  children. Write user stories + acceptance criteria.
- Engineering: add firebase_messaging (Android + iOS), token registration per
  parent device in Firestore with tight firestore.rules, a Cloud Function that
  sends the notifications, opt-in/opt-out in parent settings, notification
  permission UX. Everything must build and pass CI without real Firebase/APNs
  keys (feature off until configured).
- Security/privacy: no child personal data in payloads, tokens readable only by
  their owner, rate limits; update the privacy policy notes.
- Owner-only steps (prepare paste-ready steps; do not do them): create or
  confirm the Firebase project, upload the APNs auth key from his Apple
  Developer account, add any needed GitHub secrets.

### 2. Sheikh Abdul Rashid Sufi reciter — PR #5
- PR #5 (branch feat/reciter-abdulrashid-sufi) adds عبد الرشيد صوفي as a
  whole-surah reciter (QuranicAudio abdurrashid_sufi/{surah}.mp3) because
  EveryAyah has no per-ayah Hafs recordings for him.
- Review it (Islamic content reviewer: correct name, Hafs recitation; QA; Quality
  Gate), fix CI if needed, and merge when green.
- Verify the audio URLs actually play (emulator/CI or a real-phone run). If they
  do not, find a working source.
- Licensing: QuranicAudio forbids commercial use. Approvals & Licensing Officer:
  find the right rights holder/contact, draft the permission request as a
  "ZADX موافقات –" Gmail draft (never send), or propose self-hosting licensed
  files. Add this reciter to the reciters-licence tracker (now 5 reciters).
- Nice to have: per-ayah timing data for this reciter so ayah highlighting works.

### 3. Owner decisions — 2026-11-20 (do not ask again)
- **No music in the app at all.** Background/game music is removed (PR #10, feat/remove-music; get it green and merge). Keep sound effects, mute and the parent's sound-effects volume. Never add music back.
- Reciters without a written licence are hidden from the child's screens in store/release builds (debug builds may show them to parents marked "licence pending"). Implement with a per-reciter licence flag + test. If no reciter is confirmed, log a pre-launch blocker.

### 4. Islamic encouragement phrases after every completed task (prototype v3 done)
- Random, non-repeating phrase on the reward screen, gender-aware Arabic: "ما شاء الله، أحسنت/أحسنتِ!"، "جزاك/جزاكِ الله خيرًا!"، "بارك الله فيك/فيكِ!"، "تبارك الله! كمّل/كمّلي كده"، "جعله الله في ميزان حسناتك"، "نفع الله بك/بكِ" + English equivalents.
- Only common praise/dua phrases; never quote Quran or hadith unless the Islamic content reviewer verifies exact text + source. Add the phrase list to the sheikh review.
- Optional child form-of-address field (masculine/feminine) in the child profile; tests.

### 5. Original glossy cartoon illustrations for exercises and tasks (prototype v3 done)
- Jump rope, squats, push-ups, sit-ups, toe touch; reading, tidying, prayer mat. Boys and girls; girls modestly dressed, may wear hijab. Rounded glossy tiles, "+N دقيقة" badge.
- 100% original vector art (SVG via flutter_svg, or CustomPainter); record origin/licence in the assets registry. Never copy another company's characters or art (the owner's reference screenshots were inspiration only).

- [x] Exercise figures (branch feat/exercise-figures): original faceless kid figure per exercise (push-up, sit-up, jumping jack, squat, toe touch + generic fallback), animated on the exercise card, still with reduce-motion; tests in `test/exercise_figures_test.dart`. Next: hijab variant chosen per child, jump rope, task illustrations; device check by the Quality Gate.

### 6. "مكان الطفل / Where is my child" — parents only (prototype v3 done)
- Child safety and privacy first: off by default, opt-in per child by the parent; the child's device always shows "موقعك ظاهر لأهلك" while sharing; one-shot "locate now"; safe places (home, school, mosque) with arrival/leave alerts via the parent push system (PR #8); history kept 24 h max then deleted by a scheduled function; readable only by that family's parents (firestore.rules + tests); no third parties, no ads, no analytics on location.
- Before code: privacy & child-safety officer + CISO write docs/LOCATION_PRIVACY.md (COPPA verifiable parental consent, GDPR-K, Apple kids category + Family Controls impact, Google Play background-location + Families declarations, review notes) and list owner-only steps (store declarations, privacy policy update, maps API key with a spending cap). Record any map SDK's licence/cost; prefer no per-use cost.
- Ship behind a feature flag that stays off until the owner approves the privacy review.

### 7. Offline-first (owner decision 2026-11-21, approved)
Design: docs/ARCHITECTURE.md "Offline-first". The child side must work fully without internet.
- [x] Step 1 (branch feat/offline-first-1): `EntitlementCache` with a 7-day offline grace and
  clock-rollback guard + tests; `FeatureFlags.locationMap` (off in release) + tests.
- [ ] Wire `EntitlementCache` into `entitlementProvider`: record the tier after `verifyPurchase` /
  the server-written family doc, show the cached tier offline. Decide first what replaces the
  client-side default "Plus trial" (R-16).
- [ ] Quran text bundled as a verified Uthmani asset with attribution (today: fetched from
  api.quran.com per surah on first open, then cached). Islamic Content Reviewer picks the source;
  confirm the API is covered by the Quran Foundation approval or move to the QF API.
- [ ] Quran recitation: switch the source from everyayah.com to the Quran Foundation recitations
  API (the approved channel); optional "download for offline" to the user's own device for
  licensed reciters only; never rehost on our servers.
- [ ] Adhan: add the licensed `assets/audio/adhan_*.mp3` files (missing today) once the recordings
  licence is confirmed.
- [ ] Local DB (recommend drift, MIT) for tasks, progress, unlock timer, lock state and a queue of
  parent commands; migrate from shared_preferences.
- [ ] Sync: Firestore offline persistence (explicit on web), `commands` sub-collection with
  rules + rules tests, conflict rule "parent's latest command wins" for locks/limits.
- [ ] Parent-only offline indicator; never a blocking error on child screens.
- [ ] Offline test suite that runs with networking disabled.
- Note: `geolocator` is declared in pubspec.yaml but unused in lib/ — keep it out of child
  builds until the location review (docs/LOCATION_PRIVACY.md) is done, or remove it.

### 8. Kids Art Director — engaging backgrounds, icons and celebrations (PR feat/kids-art-backgrounds)
- New role **zadx-kids-art-director** (`.claude/agents/zadx-kids-art-director.md`): most senior visual specialist for ages 5–12; grades every screen A–F on appeal, clarity, accessibility and performance; original code-drawn art only; Islamic sensitivity (no figures, no music motifs, calm Quran screens). Audit: `docs/design/ART-AUDIT.md`.
- Built: `lib/shared/art/` (per-area `ZadSceneBackground` scenes, `ZadIcon` set, `ZadCelebrationBurst`), wired into all screens; tests in `test/kids_art_test.dart`.
- Follow-ups: Quality Gate device check of the CI APK (look + 60 fps on a low-end phone); the **web prototype should adopt the same scenes and icons**; remove the old `PatternBackground` once nothing uses it; reuse the burst for finished adhkar sections; golden tests with a bundled font.

### 9. Free plan: lock + Quran + adhan free forever (owner request 2026-11-21) — PR feat/free-plan
- [x] Feature matrix in one place (`AppFeature` / `hasFeature`, server mirror `PLAN_FEATURES`), Free card "مجاني للأبد"
  on the plans screen, paid screens gated with a kid-safe "ask a parent" card behind the parent PIN.
- [x] Free locks on prayer times + a daily time limit only (`lockTasksEnabledProvider` = `hasFeature(tasksRewards)`);
  on Free the prayer lock ends by itself 20 min after it started (feat/plans-lock-integration).
- [x] Owner decision 2026-11-21: adhkar is free (app + backend `PLAN_FEATURES`).
- [x] R-16 replaced: 7-day Plus trial from first launch, stored on device with a high-water clock
  (`TrialClock`), then Free; remaining days shown in the parent area only.
- [x] Parent PIN session re-locks after 2 min idle and when the app goes to the background / screen off.
- [ ] Native (other branch): honour `LockPolicy.prayerAutoEndMinutes` so a Free prayer lock ends without Zad X running.
- [ ] Server-side trial per family (a reinstall / clear-data restarts the on-device trial).
- [x] Rules emulator tests in CI (R-32/R-33): `@firebase/rules-unit-testing` against the Firestore emulator in the light `backend` job (`npm run test:rules`); PR #36 (2026-11-23) adds child / parent / stranger / signed-out cases replacing the manual README cases. The rest of the old PR #36 follow-ups (approveTask callable, server-side earnedMinutes/requiredDone, child-side patches) shipped in #39.
- [ ] P3 (R-32 residual): a child device can still write progress status "done" (display only, credits nothing). Option: a `childTask`-style one-entry check so child writes may set only todo/pending; needs a client change in `FirestoreFamilyRepository.saveDay`.

## Done

## Firebase status (2026-11-21, set up by Claude with the owner)
- Project "Zad X Play" (id `zad-x-play`), free Spark plan, Analytics and Gemini OFF. Sole owner: moatasemgebril@gmail.com.
- Firestore (default) created in **eur3 (Europe)**, Standard edition, production mode (deny-all until our backend/firestore.rules are deployed).
- Authentication: **Anonymous** enabled (auto clean-up OFF, so parents' anonymous accounts are not deleted after 30 days).
- Apps registered: Android `com.zadx.app`, iOS `com.zadx.app`, Web "Zad X Play Web" (no Hosting).
- iOS bundle identifier set to `com.zadx.app` in ios/scripts/add_native_files.rb (2026-11-28).
- TODO (team): run `flutterfire configure --project=zad-x-play` in CI or locally to generate firebase_options.dart.
- backend/firestore.rules (main @ 44b0782) published to the live project from the console, 2026-11-28 08:40 PT (replaces deny-all). Redeploy after every rules change. The `deviceHeartbeats` index is only for the Functions path, not deployed.
- Waiting on owner: google-services.json + GoogleService-Info.plist from the console (gitignored) to wire Android/iOS.
- Cloud Functions need the Blaze plan (card required). Owner wants zero cost: keep the app working without Functions where possible (Firestore rules + client logic), and list Blaze as an owner decision.

## Quran Foundation approval (2026-11-21, written reply from basit@quran.com)
- APPROVED: commercial kids' app with subscription may use Quran Foundation APIs, content stays inside the app (no selling/redistribution).
- Reciters approved via QF recitations APIs (all Hafs): Alafasy, Abdul Basit (murattal), Al-Husary, Al-Minshawi (murattal). Set their licence flag to confirmed.
- NOT available: Abdur-Rashid Sufi (QuranicAudio ID 109) — REMOVE from the app (P1).
- No rehosting on our servers/CDN (max 1 week cache on our servers). Users MAY download recitations to their own device for offline listening.
- Production credentials: build/test in pre-live in the QF Developer Console, then request production access there (no separate review).
- Attribution required: "Quran data provided by Quran Foundation" + credit each reciter. Adapt the children's section of QF's privacy packet.
- Optional: Quran ID sign-in → listing in the Quran App Store (quran.com/apps).
- Refs: https://api-docs.quran.foundation/legal/developer-terms/#31-acceptable-use · https://api-docs.quran.foundation/docs/tutorials/faq#what-attribution-or-copyright-information-should-i-show · https://api-docs.quran.foundation/legal/developer-privacy/

## رسالة من صاحب المشروع (2026-11-21)
معتصم بيشكر فريق ZADX كله على الشغل: الأصوات، والألعاب التعليمية، ودعم أكتر من طفل، ومراجعة الأمان، وموافقة Quran Foundation، وإعداد Firebase. جزاكم الله خيراً، كمّلوا بنفس الجودة.

## Owner feedback 2026-11-21 (iPhone web preview)
- [x] Reciter switch works instantly while playing (PR #16).
- [x] Audio plays on iPhone Safari (PR #17) — owner confirmed it works.
- [ ] On web, switching reciter restarts the surah from ayah 1 instead of the current ayah (initialIndex / currentIndex on just_audio web). Fix and add a test (P2).
- [ ] Adhan audio files still missing (assets/audio/adhan_*.mp3) — blocked on recordings licence.

## Owner request 2026-11-21: adhkar read aloud by a sheikh (P1, Approvals & Licensing)
- No freely-licensed adhkar audio found yet. Contact the official Hisn al-Muslim site (binwahaf.com, the late Sheikh Saeed bin Wahf al-Qahtani) for permission to use its audio in a paid kids app; find the official contact on the site itself. Alternatives: a recognised Islamic institution with recordings, or a local imam/sheikh recording the adhkar for us with written permission (owner then owns the recordings).
- When licensed: per-dhikr audio in adhkar_view with a play button, attribution, offline bundling.
- [ ] Owner decision 2026-11-23 (branch `feat/adhkar-quran-audio`, pending CI + Quality Gate): **Quranic
  adhkar → Mishary Alafasy via the QF-approved Quran pipeline** (voice `afasy`, `licenceConfirmed`,
  same per-ayah player as the Quran screen, `PlayerKind.quran` so effects stay silent and the adhan is
  never mixed; credit «مشاري العفاسي · Mishary Alafasy»; hidden in release if the licence flag is off;
  offline → gentle inline hint). Today this covers the three Quls of the reminder card (112, 113, 114,
  whole). No catalogue dhikr is exactly Quran ayat: hasbi is only part of At-Tawbah 9:129 (text-only);
  Ayat al-Kursi and Al-Baqarah 2:285–286 are not in the catalogue (Islamic Content Reviewer decides
  whether to add them; text would come from the Quran API, Al-Baqarah needs a SurahInfo entry).
  **Non-Quranic adhkar stay text-only until a licence for adhkar recordings exists.** Still blocked by
  the P1 above: the recitation source is everyayah.com, not a QF host, until the QF API migration.

## Findings from the 2026-11-21 PM cycle (Approvals + Marketing + Skills & Add-ons)
Details: docs/ADDONS-REGISTRY.md, docs/marketing/STORE-LISTING.md, docs/approvals/OUTREACH-2026-11-21-PM.md.
- [x] **P1 child safety:** the AI assistant card (lib/features/help/help_screen.dart) is gated only by `PaidFeatureGate`, not the parent PIN, and Help opens from the main shell → a child in a paid family can chat with the Anthropic API. Put it behind the parent gate (check whether PR #28 "assistant gate" already does this before starting). → **Fixed in fix/child-privacy-p1, pending CI** (2026-11-22): `AssistantParentLock` (lib/features/help/assistant_parent_lock.dart) reuses the parent PIN session; test/assistant_parent_lock_test.dart.
- [ ] **P1 privacy/offline:** `google_fonts` downloaded Tajawal / Baloo Bhaijaan 2 / Amiri Quran from Google at runtime on the child's device. → **Fixed in branch `fix/bundled-fonts` (2026-11-23), pending CI + Quality Gate:** the OFL TTFs from google/fonts are bundled in `assets/fonts/<family>/` (per-family OFL.txt, SHA-256 registry in docs/FONTS.md), declared under `flutter: fonts:`, and the `google_fonts` package is removed. Test: `test/bundled_fonts_test.dart`.
- [x] **P2:** `geolocator` is declared and the Android manifest asks for ACCESS_COARSE_LOCATION but no code uses it → remove until the location-map review is done (Families policy). → **Fixed in fix/child-privacy-p1, pending CI** (2026-11-22): package, ACCESS_COARSE_LOCATION and the iOS NSLocationWhenInUseUsageDescription note removed.
- [x] **P2:** commit `backend/functions/package-lock.json`, switch CI to `npm ci` → **done, pending CI, 2026-11-23 PM** (branch `addons/p2-licences-lockfile`; local `npm ci` + build + 49/49 tests pass; `npm audit --audit-level=high` passes, 10 moderate via uuid in googleapis/firebase-admin deps).
- [ ] **P2 (still open):** commit `pubspec.lock` — flutter is not available in the tooling session; CI could generate it (`flutter pub get`) and upload it as an artifact for review.
- [ ] **P2 (still open):** pin third-party GitHub Actions (dorny/paths-filter, softprops/action-gh-release, subosito/flutter-action, reactivecircus/android-emulator-runner, google-github-actions/*) to commit SHAs — needs read access to those repos to get verified SHAs; not guessed.
- [x] **P2:** the CC BY 3.0 adhan credit in lib/features/parent/credits_card.dart lacks the licence URL and the source link → **done, pending CI, 2026-11-23 PM**: licence URL, Commons source link and changes (trimmed, normalised, converted to MP3) shown as selectable text in AR/EN; test `test/credits_card_test.dart`.
- [x] **P2:** remove/trim .github/workflows/fetch-adhan.yml — re-running it would re-add CC BY-SA adhans and overwrite ADHAN-CREDITS.txt → **done, pending CI, 2026-11-23 PM**: workflow removed; adhans are added by hand only after licence review (docs/ADDONS-REGISTRY.md §3).
- **Docs:** ARCHITECTURE.md plans table still lists adhkar under Basic (owner made adhkar free on 2026-11-21); STORE_CHECKLIST says a 14-day intro offer while the app gives a 7-day trial → owner decides one.
- ~~**Owner decision:** Blaze for Cloud Functions~~ → **Decided 2026-11-28: zero cost, Spark only, no Blaze** (see "Zero-cost backend" below).

## Family setup & payment review (product manager, 2026-11-21 evening, owner question)
Flow today: same Zad X app on the parent phone and the child device (Windows = Zad X Guard); parent creates the PIN on the device (PR #28 adds a first-run PIN screen with confirm); children added in the Parent dashboard (Free 1 / Basic 2 / Plus 5); child device linked with a 6-digit code from the parent phone (10 min); payment = store in-app subscription (Google Play / App Store), verified by `verifyPurchase`; no code/password is ever sent after payment. One-device mode works offline today; linking + payments need Firebase (apps, Firestore, Blaze for Functions) and store products.
- ~~**P0:** the paid plan never reaches the child's device — the app does not read the entitlement `verifyPurchase` stores on the family doc; the child device falls back to Free after its own 7-day trial.~~ Fixed in fix/family-entitlement-restore (pending CI).
- ~~**P0:** restore on a new phone fails — each install signs in anonymously = new family; the server rejects the old purchase as used by another family. Needs a family recovery path (e.g. parent sign-in) before launch.~~ Fixed in fix/family-entitlement-restore (pending CI): restore = link the new phone from an existing parent phone ("Add a parent phone" code). The store token never auto-joins a family (AppSec: bearer secret); `verifyPurchase` answers `purchase_in_other_family` and the subscription screen explains the steps. Run `scripts/migrate-purchase-tokens.js` at deploy (backend/README.md).
- ~~**P1-3:** no way to remove a linked device (parent or child) from the family; needed so a parent can revoke a lost phone or a wrongly linked device.~~ Fixed in branch `fix/remove-linked-device` (2026-11-24, pending CI + Quality Gate + deploy): `removeLinkedDevice` callable (parent only, `last_parent` refused, same family only, audit entry, refresh tokens revoked), rules + emulator tests, Parent → Link devices → *Linked devices* → "Remove device / إزالة الجهاز". Deploy: functions first, then add a Firestore TTL policy on `audit.expiresAt` (collection group `audit`). Follow-ups below (P1-3a/b/c).
- ~~**P1-3a (follow-up):** the removed device's app only gets permission-denied errors (the wallet now ignores them and keeps its local state and lock; a removed child device stays locked, `familyPlanStatusProvider` keeps its last value). Show a "this device was removed from the family" screen and reset the device to a fresh local family.~~ Fixed in branch `fix/removed-device-p1-3a` (2026-11-28, pending CI + Quality Gate + deploy): a permission-denied on the family-doc listener is only a hint; the device counts as removed only after two explicit `{member: false}` answers from the new `checkDeviceMembership` callable (admin SDK, own uid only, rate-limited), so offline/timeouts/rules mistakes never reset a device. Then: the removed state is saved first and forces a locked policy (`removedLockPolicy`, reason `removed`) on every plan; the old family's cached data is deleted (child names, wallets, tasks, learning progress, plan cache, approval queue, family id), the session is signed out and the Firestore cache is cleared at the next start. The app shows only "هذا الجهاز أُزيل من العائلة / This device was removed from the family" until a parent enters the parent PIN, which starts a fresh family and opens the Parent area for linking again. Tests: `test/removed_device_test.dart`, backend `devices.test.js`. Deploy: functions (`checkDeviceMembership`) before the app; without it the app simply never resets (fail-safe).
- **P2 (P1-3b):** Windows guards are not members, so they are not listed/removable in the app yet (set `devices/{id}.revoked`, R-29).
- **P2 (P1-3c):** a removed parent phone's FCM token stays in `parentTokens` (tokens are not keyed by uid) → store tokens per device uid.
- ~~**P1 (merge note for PR #28):** its `redeemPairingCode` pause check runs for every non-Windows code; a parent code has no child, so it falls back to `child-1` and is refused with `child_paused` when `child-1` is paused on Free → skip that check for `target === "parent"` when both branches meet.~~ Fixed in PR #28 (2026-11-24, pending Quality Gate): `pairingRedeemRefusal({target, ...})` never refuses a parent code; backend tests cover parent code while child-1 is paused (succeeds) and child/Windows code for a paused child (`child_paused`). Same merge: the server pause check reads the per-app plans (`pausePlanOf`: an active Play or Kids plan keeps all children active) and `createFamily` stamps `createdAt` again (server-time 7-day family trial).
- **P2 (follow-up):** a newly linked parent phone keeps its own local child list; it should load the family's `children/` after switching family. The family doc's `planExpiresAt` is refreshed only when a parent phone re-verifies (every Android launch); child devices fall back to the 7-day cache if no parent opens the app after a renewal → add RTDN renewal handling that updates the family plan. Per-uid rate limits are weak (anonymous uids are free): IP, global and per-family limits carry the load.
- **P0 (before iOS):** App Store receipt verification returns `unimplemented`.
- ~~**P1:** no way to link a second parent phone (every redeemed code becomes a child device).~~ Fixed in fix/family-entitlement-restore (pending CI): Link devices → "Add a parent phone".
- ~~**P1:** no PIN recovery (store-account or email-based reset that a child can't trigger).~~ Fixed in fix/pin-recovery (pending CI + Quality Gate): offline recovery code (XXXX-XXXX-XXXX) shown once at PIN setup, salted PBKDF2 hash only, "Forgot PIN?" on the gate (code → new PIN → new code), stricter lock-out; installs without a code get a parent-area card. Later step: store-account / email reset once Firebase is live.
- ~~**P1:** even after PR #28, the paid-plan assistant lives on the Help screen, which children can open → put it behind the parent PIN.~~ Already fixed by `AssistantParentLock` (lib/features/help/assistant_parent_lock.dart, test/assistant_parent_lock_test.dart); stale line closed 2026-11-28.
- FAQ faq6–faq12 + new step 1 added (help/faq-setup-payment); faq8/10/11 describe the launch flow and depend on the P0 fixes + Firebase.
- PR #32 AppSec re-review (B → A after fixes): `parentDevices` added to serverOnlyFamilyKeys (done). Open P2: remove/revoke a linked phone (parent-only action); parent link code → 8–10 chars + confirmation on the issuing phone; server-side PIN check for code creation. Legacy child phones without `childDevices` would count as parents — no production families exist yet (Firebase not live), so no backfill needed; re-check before launch.

## Zero-cost backend (owner decision 2026-11-28) — Phase 1 DONE (PR #54 + #55, CI green)
Done: pairing, device removal/membership, task approve/reject, free child, audit → Firestore rules (53 emulator rules tests); purchases on device + parent shares the plan; AI assistant and referral rewards hidden; in-app family alerts + last seen instead of push; `FeatureFlags.serverFunctions` off. Details: docs/ZERO-COST-BACKEND.md, docs/decisions/SPARK-APP-NO-FUNCTIONS.md.
**Phase 2 (next):** Windows Guard on Firestore (no HTTP functions); remove the `cloud_functions` dependency once nothing needs it; App Check (free) enforced on Firestore before launch; FLAG_SECURE on code screens; on-device subscription check tests on a real phone; deploy rules with `firebase deploy --only firestore:rules` (free).
Original plan (kept for reference):
Spark (free) has Auth + Firestore + Hosting but **no Cloud Functions / Secret Manager**. Every callable must get a free design or be dropped:
- Pairing codes (`createPairingCode`/`redeemPairingCode`), task approval (`approveTask`), device removal (`removeLinkedDevice`, `checkDeviceMembership`): move to Firestore rules + client writes (rules-enforced invariants, emulator tests); removed device = member doc missing, read by rules.
- Store purchase verification (`verifyPurchase`, RTDN): no server → rely on on-device store APIs (Play Billing / StoreKit 2 signed transactions) with the 7-day cached entitlement; accept the weaker anti-fraud; never trust a client-written plan for other devices without a parent device re-check.
- AI assistant (Anthropic key needs a server secret): hide it until a free safe option exists — a key must never ship in the app.
- Windows Guard HTTP API (`devicePolicy`/`reportUsage`): Firestore with a per-device auth account instead of HTTP functions.
- Tamper heartbeats (`checkHeartbeats`, scheduled): parent device checks last-seen when it opens the app.
- Windows code signing: no paid certificate → ship unsigned with clear SmartScreen steps for parents, or drop Windows Guard from v1 (owner call later).
- Privacy policy/COPPA/GDPR-K: in-house from official free guidance (no lawyer).
