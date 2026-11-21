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

### 6. "مكان الطفل / Where is my child" — parents only (prototype v3 done)
- Child safety and privacy first: off by default, opt-in per child by the parent; the child's device always shows "موقعك ظاهر لأهلك" while sharing; one-shot "locate now"; safe places (home, school, mosque) with arrival/leave alerts via the parent push system (PR #8); history kept 24 h max then deleted by a scheduled function; readable only by that family's parents (firestore.rules + tests); no third parties, no ads, no analytics on location.
- Before code: privacy & child-safety officer + CISO write docs/LOCATION_PRIVACY.md (COPPA verifiable parental consent, GDPR-K, Apple kids category + Family Controls impact, Google Play background-location + Families declarations, review notes) and list owner-only steps (store declarations, privacy policy update, maps API key with a spending cap). Record any map SDK's licence/cost; prefer no per-use cost.
- Ship behind a feature flag that stays off until the owner approves the privacy review.

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
