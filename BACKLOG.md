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

## Done
