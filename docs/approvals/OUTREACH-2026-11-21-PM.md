# Approvals outreach — 2026-11-21 (PM cycle)

Prepared by the Approvals & Licensing Officer. **Sent 2026-11-21 PM by the orchestrator (drafts 1–4, BCC owner; draft 4 edited to drop an unverified "operated from Egypt" line).** The orchestrator sends the
emails and then updates `security/APPROVALS-TRACKER.md` (status, date sent).

Rule used: an address is listed only if it was seen on the organisation's own website on
2026-11-21 (opened with WebFetch). No third-party directories, no personal addresses.

## 1. Verified contacts

| # | Party | Need | Contact | Official source URL | Verified? | Form only? |
|---|---|---|---|---|---|---|
| 1 | Dar al-Ifta al-Misriyya (دار الإفتاء المصرية) | Review of adhkar texts/counts and prophets quiz | info@dar-alifta.org (also published: ask@dar-alifta.org) | https://dar-alifta.org/ar/services (footer "اتصل بنا" + top bar) | Yes | No (fatwa request form also exists: https://dar-alifta.org/ar/fatwa/fatwa-request) |
| 2 | Abu-Ghazaleh Intellectual Property (AGIP) | Trademark clearance search "Zad X" / "Zad X Play" (Egypt, GCC, US) | agip@agip.com | https://www.agip.com/news/en/news/22309 (Head Office block; contact page https://www.agip.com/Contact-Us/en) | Yes (on agip.com; the separate HQ page https://www.agip.com/page/en/hq could not be opened) | No |
| 3 | Sectigo | Windows code signing (OV vs EV) — information + prices | sales@sectigo.com | https://sectigo.com/about/contact ("Email sales") | Yes | No |
| 3b | DigiCert (alternative) | Same | No sales email published; sales by phone (US +1-801-770-1701, UK +44 800 066 8588) or live chat | https://digicert.com/contact-us | Yes (no email) | Phone/chat only — not emailed |
| 3c | Microsoft Azure Trusted Signing (alternative) | Same, no email needed | Sign-up in the Azure portal (owner account) | — not opened this cycle | No | Portal only (**OWNER**) |
| 4 | ZwillGen PLLC (Children's Privacy & EdTech practice) | Quote: privacy policy, referral terms, COPPA/GDPR-K review, child geolocation consent | info@zwillgen.com | https://www.zwillgen.com/practices/children-privacy-ed-tech (footer, mailto) | Yes | No |
| 5 | Adhan recording (ejaz215, Freesound 33937, CC BY 3.0) | Confirm attribution | No email needed | https://commons.wikimedia.org/wiki/File:33937_ejaz215_call-to-prayer-from-the-prophet-s-mo.ogg (from ADHAN-CREDITS.txt; not reopened) | n/a | n/a |
| 6a | Microsoft (Family Safety / Xbox names) | Naming rules | trademarks@microsoft.com — **already contacted 2026-11-21, do not repeat** | https://microsoft.com/legal/intellectualproperty/trademarks ("Resources") | Yes | No |
| 6b | Sony Interactive Entertainment (PlayStation Family) | Naming rules | No trademark/legal email published | https://www.playstation.com/en-bg/legal/copyright-and-trademark-notice/ ; licensing program (peripherals only, form): https://www.playstation.com/official-licensing-program/ | Yes (no email) | Form only, and not the right channel — **no email** |

Existing tracker rows checked:

| Party | Address | Result |
|---|---|---|
| PRIVO | info@privo.com | **Verified** — https://privo.com/contact (footer "Contact us") |
| Microsoft | trademarks@microsoft.com | **Verified** — https://microsoft.com/legal/intellectualproperty/trademarks |
| Quran Foundation | developers@quran.com | **Not verified** — https://quran.com/developers lists no email (feedback form + GitHub issues only); https://api-docs.quran.foundation/ could not be opened this cycle. Approval already received, so no action needed. |

### Notes and decisions
- **Adhan (item 5):** the bundled recording is CC BY 3.0. The parent-area Credits card
  (`lib/features/parent/credits_card.dart`) shows the author (ejaz215), licence name, source
  (Freesound / Wikimedia Commons) and that it was "converted and trimmed" — the core attribution
  duties are met. **Gap (small):** CC BY 3.0 §4(b) also asks for the licence URI and, where
  practical, a link to the source. Recommend adding the text
  `https://creativecommons.org/licenses/by/3.0/` and the Commons file URL to the Credits card
  (engineering, P2). `android/app/src/main/res/raw/adhan_short.mp3` is an excerpt of the same
  recording, so the same credit covers it. The tracker row about "four bundled adhans" is out of
  date and has been updated.
- **Microsoft guidelines (6a):** app names, icons and screenshots must not contain Microsoft brands;
  the description may truthfully say the app works with a Microsoft product, without implying
  endorsement. Keep plain descriptive wording (e.g. "works alongside Microsoft Family Safety") and
  add a trademark footnote. Wait for the reply already pending.
- **Sony (6b):** no published contact for trademark questions. Do not name PlayStation in the app
  name/icon; use plain descriptive text plus a trademark notice ("PlayStation is a registered
  trademark of Sony Interactive Entertainment Inc."). Revisit only if the store reviewer objects.
- **Code signing:** one email (Sectigo). DigiCert = phone/chat by the owner if he wants a second
  quote. Azure Trusted Signing needs the owner's Azure account and identity validation.
- **Trademark:** AGIP covers Egypt and the GCC directly; the email also asks about US coverage. A
  second quote (e.g. a US-only firm) can be sought in a later cycle.

## 2. Drafts (ready to send — plain text, no attachments)

### Draft 1 — Dar al-Ifta al-Misriyya
**To:** info@dar-alifta.org
**Subject:** ZADX موافقات – طلب مراجعة شرعية لأذكار ومسابقة قصص الأنبياء في تطبيق تعليمي للأطفال

السلام عليكم ورحمة الله وبركاته،

أنا معتصم جبريل، مؤسس تطبيق "Zad X Play"، وهو تطبيق تعليمي إسلامي للأطفال (من 5 إلى 12 سنة) ما زال قيد التطوير ولم يُطلق بعد.

يتضمن التطبيق:
- مجموعة من أذكار الصباح والمساء والأذكار اليومية، بنصوصها وعدد تكرار كل ذكر ومصدره.
- مسابقة قصيرة عن قصص الأنبياء عليهم السلام بأسئلة مبسطة للأطفال.

نحرص على أن يكون كل ما يُقدَّم للأطفال صحيحًا ومُوثَّقًا، لذا نرجو التكرم بإفادتنا:
1. هل تقدم دار الإفتاء خدمة مراجعة علمية لمحتوى مكتوب من هذا النوع؟
2. ما الطريقة المعتمدة لتقديم الطلب (البريد الإلكتروني أو نموذج أو خطاب رسمي)؟
3. هل توجد رسوم أو مدة متوقعة للمراجعة؟

يسعدنا إرسال النصوص كاملة مع مصدر كل بند بالصيغة التي تحددونها.

وجزاكم الله خيرًا.

Moatasem Gebril, Founder, Zad X Play, moatasemgebril@gmail.com

---

### Draft 2 — AGIP (trademark clearance)
**To:** agip@agip.com
**Subject:** ZADX موافقات – Trademark clearance search quote: "Zad X" / "Zad X Play"

Dear AGIP team,

I am the founder of Zad X Play, an educational Islamic app for children that is currently in
development (not yet launched). Before launch I would like a trademark clearance search for the
names "Zad X" and "Zad X Play".

Likely classes: 9 (downloadable software / mobile apps), 41 (educational and entertainment
services) and 42 (software as a service).

Could you please let me know:
1. Whether you can run clearance searches in Egypt and the GCC countries, and whether you also
   cover the United States (directly or through associates).
2. Your fees and turnaround time for the search, per country and per class.
3. Indicative fees for filing afterwards, in case the names are clear.
4. What information you would need from me to start.

This is a request for information and a quote only.

Kind regards,
Moatasem Gebril, Founder, Zad X Play, moatasemgebril@gmail.com

---

### Draft 3 — Sectigo (code signing)
**To:** sales@sectigo.com
**Subject:** ZADX موافقات – Code signing certificate information request (OV vs EV)

Hello,

I am the founder of Zad X Play, a children's education app in development (not yet launched). We
will ship a Windows desktop component and need to sign it with Authenticode.

Could you please send me:
1. Your current prices for OV and EV code signing certificates (1 and 3 years).
2. The practical difference between OV and EV for Windows SmartScreen reputation today.
3. The identity/organisation verification steps for a sole founder, and for a newly formed LLC.
4. The supported key storage options (hardware token, cloud HSM / remote signing) and any extra
   cost for each.

This is an information request only.

Thank you,
Moatasem Gebril, Founder, Zad X Play, moatasemgebril@gmail.com

---

### Draft 4 — ZwillGen (children's privacy)
**To:** info@zwillgen.com
**Subject:** ZADX موافقات – Children's privacy counsel: request for scope and fee quote

Dear ZwillGen team,

I am the founder of Zad X Play, an Islamic educational app for children aged 5–12, with a parent
dashboard and subscriptions. The app is in development and has not launched. We plan to offer it
to families in the US, EU/UK, Egypt and the Gulf. I saw your
Children's Privacy & EdTech practice and would like to ask whether you could help, and at what cost.

Possible scope:
1. Drafting or reviewing our privacy policy and in-app notices.
2. Reviewing the terms of a parent-to-parent referral program.
3. A COPPA and GDPR-K (Art. 8 / UK Children's Code) compliance review, including the verifiable
   parental consent method.
4. One specific question: can a kids' app collect a child's approximate
   location, with logged parental consent and deletion after 24 hours, for parents in the US,
   EU/UK, Egypt and the Gulf? What consent method and DPIA would be required?

Could you tell me whether this is within your practice, whether you would need local counsel for
Egypt/GCC, and your fee structure (fixed fee per item or hourly estimate)? This is a request for
information only; I will share details only after we agree on engagement terms.

Kind regards,
Moatasem Gebril, Founder, Zad X Play, moatasemgebril@gmail.com

---

No drafts for: DigiCert (no sales email), Azure Trusted Signing (portal, owner), Microsoft (already
contacted), Sony (no published channel; not needed), adhan rights holder (CC BY 3.0, no permission
needed).
