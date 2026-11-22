# ZADX Backlog

The orchestrator reads this file at the start of every cycle (see CLAUDE.md).
Owner requests come first within the priority order. Close an item by moving it
to "Done" with the PR link; record decisions in the ZADX LOG.

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

## Done

## Firebase status (2026-11-21, set up by Claude with the owner)
- Project "Zad X Play" (id `zad-x-play`), free Spark plan, Analytics and Gemini OFF. Sole owner: moatasemgebril@gmail.com.
- Firestore (default) created in **eur3 (Europe)**, Standard edition, production mode (deny-all until our backend/firestore.rules are deployed).
- Authentication: **Anonymous** enabled (auto clean-up OFF, so parents' anonymous accounts are not deleted after 30 days).
- Apps registered: Android `com.zadx.app`, iOS `com.zadx.app`, Web "Zad X Play Web" (no Hosting).
- TODO (team): set the iOS bundle identifier to `com.zadx.app` in ios/scripts/add_native_files.rb (flutter create defaults to `com.zadx.zadx`); run `flutterfire configure --project=zad-x-play` in CI or locally to generate firebase_options.dart; deploy backend/firestore.rules (free via `firebase deploy --only firestore:rules`).
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

## Findings from the 2026-11-21 PM cycle (Approvals + Marketing + Skills & Add-ons)
Details: docs/ADDONS-REGISTRY.md, docs/marketing/STORE-LISTING.md, docs/approvals/OUTREACH-2026-11-21-PM.md.
- **P1 child safety:** the AI assistant card (lib/features/help/help_screen.dart) is gated only by `PaidFeatureGate`, not the parent PIN, and Help opens from the main shell → a child in a paid family can chat with the Anthropic API. Put it behind the parent gate (check whether PR #28 "assistant gate" already does this before starting).
- **P1 privacy/offline:** `google_fonts` downloads Tajawal / Baloo Bhaijaan 2 / Amiri Quran from Google at runtime on the child's device. Bundle the OFL fonts in assets and set `GoogleFonts.config.allowRuntimeFetching = false` (or drop the package).
- **P2:** `geolocator` is declared and the Android manifest asks for ACCESS_COARSE_LOCATION but no code uses it → remove until the location-map review is done (Families policy).
- **P2:** commit `pubspec.lock` and `backend/functions/package-lock.json`, switch CI to `npm ci`; pin third-party GitHub Actions (dorny/paths-filter, softprops/action-gh-release) to commit SHAs.
- **P2:** the CC BY 3.0 adhan credit in lib/features/parent/credits_card.dart lacks the licence URL and the source link.
- **P2:** remove/trim .github/workflows/fetch-adhan.yml — re-running it would re-add CC BY-SA adhans and overwrite ADHAN-CREDITS.txt.
- **Docs:** ARCHITECTURE.md plans table still lists adhkar under Basic (owner made adhkar free on 2026-11-21); STORE_CHECKLIST says a 14-day intro offer while the app gives a 7-day trial → owner decides one.
- **Owner decision:** Cloud Functions + Secret Manager need the Blaze plan (Spark can't run them); decide Blaze with a budget alert/cap before backend launch.

## Family setup & payment review (product manager, 2026-11-21 evening, owner question)
Flow today: same Zad X app on the parent phone and the child device (Windows = Zad X Guard); parent creates the PIN on the device (PR #28 adds a first-run PIN screen with confirm); children added in the Parent dashboard (Free 1 / Basic 2 / Plus 5); child device linked with a 6-digit code from the parent phone (10 min); payment = store in-app subscription (Google Play / App Store), verified by `verifyPurchase`; no code/password is ever sent after payment. One-device mode works offline today; linking + payments need Firebase (apps, Firestore, Blaze for Functions) and store products.
- ~~**P0:** the paid plan never reaches the child's device — the app does not read the entitlement `verifyPurchase` stores on the family doc; the child device falls back to Free after its own 7-day trial.~~ Fixed in fix/family-entitlement-restore (pending CI).
- ~~**P0:** restore on a new phone fails — each install signs in anonymously = new family; the server rejects the old purchase as used by another family. Needs a family recovery path (e.g. parent sign-in) before launch.~~ Fixed in fix/family-entitlement-restore (pending CI): restore = link the new phone from an existing parent phone ("Add a parent phone" code). The store token never auto-joins a family (AppSec: bearer secret); `verifyPurchase` answers `purchase_in_other_family` and the subscription screen explains the steps. Run `scripts/migrate-purchase-tokens.js` at deploy (backend/README.md).
- **P1-3 (open):** no way to remove a linked device (parent or child) from the family; needed so a parent can revoke a lost phone or a wrongly linked device.
- **P1 (merge note for PR #28):** its `redeemPairingCode` pause check runs for every non-Windows code; a parent code has no child, so it falls back to `child-1` and is refused with `child_paused` when `child-1` is paused on Free → skip that check for `target === "parent"` when both branches meet.
- **P2 (follow-up):** a newly linked parent phone keeps its own local child list; it should load the family's `children/` after switching family. The family doc's `planExpiresAt` is refreshed only when a parent phone re-verifies (every Android launch); child devices fall back to the 7-day cache if no parent opens the app after a renewal → add RTDN renewal handling that updates the family plan. Per-uid rate limits are weak (anonymous uids are free): IP, global and per-family limits carry the load.
- **P0 (before iOS):** App Store receipt verification returns `unimplemented`.
- ~~**P1:** no way to link a second parent phone (every redeemed code becomes a child device).~~ Fixed in fix/family-entitlement-restore (pending CI): Link devices → "Add a parent phone".
- **P1:** no PIN recovery (store-account or email-based reset that a child can't trigger).
- **P1:** even after PR #28, the paid-plan assistant lives on the Help screen, which children can open → put it behind the parent PIN.
- FAQ faq6–faq12 + new step 1 added (help/faq-setup-payment); faq8/10/11 describe the launch flow and depend on the P0 fixes + Firebase.
- PR #32 AppSec re-review (B → A after fixes): `parentDevices` added to serverOnlyFamilyKeys (done). Open P2: remove/revoke a linked phone (parent-only action); parent link code → 8–10 chars + confirmation on the issuing phone; server-side PIN check for code creation. Legacy child phones without `childDevices` would count as parents — no production families exist yet (Firebase not live), so no backfill needed; re-check before launch.
