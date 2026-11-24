# Pricing by country and pre-launch plan: Zad X Play

Status: DRAFT 2026-11-23 (zadx-marketing-director). **Not approved.** Every price below is a
**suggestion, and the owner decides**. Nothing in this file commits Zad X to a price, a date or a claim. Needs Quality Gate review
before any part is used. Audience: **parents only**. Never address the child, and never place
marketing where children are the intended viewers.

Related: `docs/marketing/STORE-LISTING.md` (claims A1–A10, the "never use" list),
`docs/marketing/PRICING-STRATEGY.md` (pricing rationale), `docs/STORE_CHECKLIST.md`.

Owner-approved base prices (USD): **Basic $4.99/mo or $39.99/yr; Plus $7.99/mo or $59.99/yr.**
Open owner questions (unchanged by this file): trial length (7 days in-app vs 14 days store intro offer,
so the trial is **not mentioned anywhere** here, per A9). On «مجانًا للأبد»: STORE-LISTING A1 already
records an owner decision (2026-11-21) that "forever / للأبد" is not used anywhere. This file follows
that decision. If the owner still treats it as open, the safe default stays "not used".

---

## 1. Price suggestions by country (suggestion, and the owner decides)

### 1.1 Store rules that shape the table (re-check each one in the console before setting prices)

Caveat: the web search returned links to the official pages below but not their full text. The rules
are summarised from those pages' known content and from general knowledge. **Engineering/owner must
confirm each one in App Store Connect and Play Console** before setting prices.

**Apple App Store**
- Prices come from a fixed set of price points per storefront (Apple widened this to about 900 points in
  2022–2023, from very low prices up to very high ones, with points that no longer have to end in .99).
  You cannot type an arbitrary number. Pick the nearest point in each currency.
- You choose a **base storefront**. Apple then generates equalized prices for all other storefronts
  from exchange rates and taxes. You can **manually override** any storefront. Apple may update the
  auto-generated prices when taxes or exchange rates change. Manually set prices stay as you set them.
- Outside the US and Canada, App Store prices shown to customers **include applicable taxes (VAT/GST)**.
  In the US and Canada, sales tax is added on top.
- Subscription price **increases** for existing subscribers can need their consent (above certain
  thresholds/regions). Lowering a price is easy and raising one is hard, so **do not launch below the
  price we intend to keep**. Use introductory offers (once the trial question is decided) instead of a
  low list price.

**Google Play**
- Each currency has an allowed **minimum and maximum price range** per product. Play Console lists the
  ranges per country.
- Play can auto-convert from a default price using exchange rates and local pricing conventions, and
  **pricing templates** let one price set apply to many products. Local prices can be overridden per country.
- In many countries (EU, UK, Gulf VAT countries, Egypt, Malaysia, Indonesia, Turkey and others) the
  price you set is **tax-inclusive**, and Google remits the tax. In the US and Canada tax is added at checkout.
- Some currencies may not be supported for every product type. If a country is billed in USD, set the USD price.

**What this means for us**
1. Set the US as the base and **manually set** the 13 priority markets below. Leave the rest on auto.
2. Keep the annual plan at about 8 months of the monthly price (US: $39.99 vs $59.88, about 33% off;
   Plus $59.99 vs $95.88, about 37% off) in every country, so the message stays consistent.
3. Use the same local number on both stores wherever both offer that price point.
4. Re-check high-inflation currencies (TRY, EGP, PKR) **every quarter**. Do not leave them on auto,
   because a sudden auto change would confuse parents.

### 1.2 Purchasing-power reasoning

- **High-income, USD-pegged Gulf (SA, AE, KW, QA):** about the US price. Parents there are used to US-level
  app prices, and the riyal/dirham/riyal pegs keep the numbers stable. No discount needed.
- **Western Muslim diaspora (US, UK, CA, DE, FR):** list price close to the US price. The VAT-inclusive
  stores (UK/EU) are rounded to a familiar local number rather than charging the VAT on top.
- **Middle-income, large Muslim populations (EG, MY, ID, TR, PK):** about 35–50% of the US price, because
  household income is a fraction of US levels. These are the markets where volume and word of mouth matter
  most. A price parents find unfair here creates piracy and one-star reviews.
- Exchange rates below are **approximate (late 2026) and must be re-checked** on the day prices are set.

### 1.3 Suggestion table (all prices are suggestions, and the owner decides)

Prices are in local currency and **as the parent sees them** (tax-inclusive except US/CA). "≈ USD" is
rough and FX-dependent.

| Market | Store currency (verify) | Tax in shown price (verify) | Basic monthly | Basic yearly | Plus monthly | Plus yearly | ≈ USD Basic mo / yr | Reasoning |
|---|---|---|---|---|---|---|---|---|
| United States | USD | No (sales tax added) | $4.99 | $39.99 | $7.99 | $59.99 | 4.99 / 39.99 | Base storefront (owner-approved) |
| United Kingdom | GBP | Yes, VAT 20% | £4.49 | £34.99 | £6.99 | £52.99 | ~5.9 / ~46 incl. VAT | Rounded VAT-inclusive equivalent. Do not pass the full VAT on top |
| Canada | CAD | No (GST/HST added) | CA$6.99 | CA$54.99 | CA$10.99 | CA$79.99 | ~5.1 / ~40 | FX equivalent of US |
| Germany / France (EU, EUR) | EUR | Yes, VAT 19% DE / 20% FR | €4.99 | €39.99 | €7.99 | €59.99 | ~5.6 / ~45 incl. VAT | One EUR price across the EU keeps it simple. The VAT difference between DE and FR is absorbed |
| Saudi Arabia | SAR | Yes, VAT 15% | 18.99 SAR | 149.99 SAR | 29.99 SAR | 219.99 SAR | ~5.1 / ~40 | Peg 3.75. About US level, a high-income market |
| UAE | AED | Yes, VAT 5% | 18.99 AED | 149.99 AED | 29.99 AED | 219.99 AED | ~5.2 / ~41 | Peg 3.6725. About US level |
| Kuwait | Apple has historically used USD here. Google: KWD (verify) | No VAT currently (verify) | $4.99 or 1.490 KWD | $39.99 or 11.990 KWD | $7.99 or 2.490 KWD | $59.99 or 17.990 KWD | ~4.9 / ~39 | US level. Use USD if the storefront is USD |
| Qatar | Apple has historically used USD here. Google: QAR (verify) | No VAT currently (verify) | $4.99 or 17.99 QAR | $39.99 or 144.99 QAR | $7.99 or 28.99 QAR | $59.99 or 214.99 QAR | ~4.9 / ~40 | Peg 3.64. US level |
| Egypt | EGP (verify on Apple) | Yes, VAT 14% on digital services (verify) | 99 EGP | 799 EGP | 149 EGP | 1,199 EGP | ~2.0 / ~16 | About 40% of US. Core Arabic market, very price-sensitive. Re-check quarterly (FX) |
| Malaysia | MYR | Yes, SST on digital services (verify the rate) | RM 14.90 | RM 119.90 | RM 22.90 | RM 179.90 | ~3.5 / ~28 | About 70% of US. Middle-upper income, strong Islamic-app market |
| Indonesia | IDR | Yes, VAT ~11–12% (verify) | Rp 39.000 | Rp 299.000 | Rp 59.000 | Rp 449.000 | ~2.4 / ~18 | About 45% of US. Largest Muslim population, volume market |
| Turkey | TRY | Yes, VAT 20% (verify for any digital-service levy) | ₺99.99 | ₺799.99 | ₺149.99 | ₺1,199.99 | ~2.4 / ~19 | About 45% of US. High inflation: **manual price, review quarterly** |
| Pakistan | PKR (verify on Apple) | Varies by province/payment method (verify) | Rs 499 | Rs 3,999 | Rs 799 | Rs 5,999 | ~1.8 / ~14 | About 35% of US. Lowest-income priority market. Many parents pay via carrier billing on Play |

Notes:
- Snap each figure to the **nearest valid price point** in each console. If a figure does not exist as a
  point, pick the closest **lower** one in the middle-income markets and the closest point in the others.
- The lower EG/ID/TR/PK prices should be **set once and kept**, because raising them later needs subscriber consent
  in many cases (see 1.1). They are not launch promotions and must not be advertised as "discounts".
- Store descriptions keep saying "Prices in USD; your local price is shown before you pay"
  (STORE-LISTING section 3/4). **Never print local prices in marketing until the owner approves them (A9).**

**Owner decisions needed (pricing):** (a) approve or modify each row; (b) one EUR price for all EU or per
country; (c) USD vs local currency in Kuwait/Qatar if both stores allow it; (d) quarterly review owner for
TRY/EGP/PKR; (e) trial length (still open, A9).

---

## 2. Privacy-safe 30-day pre-launch plan (parents only)

### 2.1 Timing: Ramadan 2027

- Ramadan 1448 AH is **expected to begin around 8 February 2027** (astronomical forecasts reported by UAE
  outlets). Eid al-Fitr is expected **around 9–10 March 2027**. The actual dates depend on moon sighting
  and can differ by a day or so by country. **Never print a fixed date in marketing.** Write «رمضان
  القادم» / "this Ramadan" or "expected around…".
- Parents set up routines **before** Ramadan, so the ideal store launch is **about 1 week before Ramadan
  (target ~1 Feb 2027)**. That puts the 30-day pre-launch at **~2 Jan → ~31 Jan 2027**.
- **Launch gate (non-negotiable, ranked above marketing):** we launch only if the Quality Gate is at Grade A, Apple has
  approved the Family Controls entitlement, the adhan recordings are licensed (A3), the adhkar have scholar
  review, and legal/privacy sign-off is done. **If any of these is missing, we do not rush.** Fallback: keep
  the waitlist plus helpful Ramadan content for parents during Ramadan, with no app download CTA, and
  launch **after Eid al-Fitr** (mid-to-late March 2027). The plan below works for either date. Shift it by D-day.

### 2.2 Privacy rules for all pre-launch work

1. **No child data, anywhere.** The waitlist collects: parent email (required), preferred language (AR/EN,
   optional), country (optional, for pricing and prayer-city planning). **No** child names, ages, photos,
   schools or classes. No "how many kids" field (not needed yet).
2. **Double opt-in:** sign-up → confirmation email → only confirmed addresses get mail. Unconfirmed addresses
   are deleted after 7 days. Each email has a one-click unsubscribe. Checkbox (not pre-ticked):
   - AR: «أوافق على تلقّي رسائل من Zad X عن موعد إطلاق التطبيق. أنا وليّ أمر وعمري ١٨ سنة أو أكثر. يمكنني إلغاء الاشتراك في أي وقت.»
   - EN: "I agree to receive emails from Zad X about the app launch. I am a parent or guardian aged 18 or over. I can unsubscribe at any time."
   - Link to the privacy notice. State the retention period (suggestion: deleted 6 months after launch unless the
     parent becomes a customer or re-consents. Privacy officer decides).
3. **Landing page:** no third-party ad pixels, no social-media trackers, no session replay, no
   fingerprinting. If we measure visits at all, use cookieless, aggregate-only, preferably self-hosted
   analytics, only after Privacy Officer sign-off. Email provider under a DPA, EU/UK data transfer terms checked.
4. **No custom-audience uploads:** do not upload waitlist emails (hashed or not) to Meta/Google/TikTok.
   The waitlist was collected for launch news only.
5. **Paid social (if any):** parent-only targeting (adults 25+ where available). No interest targeting
   built around children's content. No ads placed in kids' content, YouTube Kids, or kids' game placements.
   Creative speaks to parents.
6. **Mosques and schools:** we speak to the administration and to parents. We never collect data via
   children, never hand flyers to children, never run in-class demos, never place posters in children's
   areas, and never offer children prizes for sign-ups.
7. **No endorsement implied:** a mosque or school hosting a flyer or a parents' talk is *not* an
   endorsement. Never write "recommended by [mosque/school]" without written permission **and** owner
   approval. Never write "scholar-approved".
8. **Religious content:** Ramadan posts and emails may use **no Quran verse, hadith or dua text** unless
   it comes from a verified source and the Islamic Content Reviewer has approved it. The default is plain
   helpful wording with no quotations.

### 2.3 Content pillars

| # | Pillar | What it covers (parent-facing) | Guardrails |
|---|---|---|---|
| P1 | Calm screen time, Islamic rhythm | How games unlock after prayer and tasks, with the parent approving | Reward is secondary: «الصلاة لله، والجائزة تشجيعٌ لك» (already in-app, see STORE-LISTING section 1) |
| P2 | Ramadan family routines | Practical parent tips: daily task lists, suhoor/iftar-time screen limits, a family Quran time | No hadith/verses without reviewer sign-off. No fixed Ramadan date |
| P3 | Parent in control | PIN-protected parent area, approvals, purchases behind the PIN | Factual features only. Lock lines only if A8 is cleared |
| P4 | Transparent building | "What we will not do": no child names required, no trackers on the waitlist | Privacy claims about the **app** need A7 and A2 sign-off first. Waitlist-page claims are ours to keep |
| P5 | Community | Mosque and Islamic-school parent sessions, parent Q&A by email | No endorsement wording. Partners named only with written permission |

### 2.4 Mosque and Islamic-school outreach (parents and administrators only)

- **Who:** 15–25 mosques/Islamic centres and 10–15 Islamic weekend/full-time schools across 3–4 pilot
  cities (suggestion: one UK city, one US city, plus Cairo and Riyadh or Dubai for Arabic-first feedback).
  Pick via the team's own contacts. No scraped lists, no cold bulk email.
- **Offer (no money changes hands at pre-launch):**
  - A one-page **parent flyer** (AR/EN), a QR code to the waitlist page, and a plain-language privacy note.
  - A 20-minute **parents' talk/Q&A** after a community event or parents' evening, only if the
    administration invites it. Topic: healthy screen time in a Muslim home (P1/P2). The app is mentioned
    at the end, not sold.
  - A short **newsletter blurb** for the school's parent newsletter.
  - Optional: a partner code that is **per institution, not per child**, so we can count aggregate
    sign-ups per partner without identifying any family. Use it only on the parent waitlist.
- **Never:** child-facing posters, flyers sent home in children's bags without the school's parent-comms
  process, prizes for children, data collection in class, "endorsed by" claims.
- **Thank-you:** a free Plus year for the institution's staff accounts is possible later, **but only if
  owner and legal approve**, disclosed, and not tied to recommendations.

**Outreach email (to administrators), AR:**
> السلام عليكم ورحمة الله،
> نحن فريق Zad X، نُعِدّ تطبيقًا عائليًا يساعد أولياء الأمور على تنظيم وقت أطفالهم على الأجهزة بروح إسلامية: الألعاب تُفتح بعد الصلاة وإنجاز المهام، ووليّ الأمر هو من يعتمد كل شيء.
> نودّ أن نعرض على أولياء الأمور في مجتمعكم نشرة تعريفية أو جلسة قصيرة عن تنظيم وقت الشاشة في البيت المسلم، إن رأيتم ذلك مناسبًا. لا نجمع أي بيانات عن الأطفال، ولا نتواصل معهم مباشرة.
> مع خالص الشكر، فريق Zad X

**Outreach email, EN:**
> Assalamu alaikum,
> We are the Zad X team. We are building a family app that helps parents shape their children's screen time around Islamic habits: games unlock after prayer and tasks, and the parent approves everything.
> If you think it suitable, we would like to offer your parents a short information sheet or a brief talk on screen time in a Muslim home. We collect no data about children and never contact them directly.
> With thanks, the Zad X team

### 2.5 The 30 days (D = launch day; dates assume D ≈ 1 Feb 2027)

| Days | Week focus | Actions | Output |
|---|---|---|---|
| D-30 → D-24 | **Foundations** | Waitlist page AR/EN live (RTL-first), double opt-in tested, privacy notice live; flyer + newsletter blurb drafted; Islamic Content Reviewer checks any religious wording; outreach list of 25–40 institutions from own contacts | Waitlist live; flyer approved by Quality Gate |
| D-23 → D-17 | **Community** | Send administrator emails; book 5–8 parents' talks; social posts 1–2 (section 3); welcome email #1 to confirmed sign-ups ("what Zad X is, what it is not") | Partner bookings; posts live |
| D-16 → D-9 | **Ramadan readiness** | Parents' talks begin; Ramadan routine content (P2) with no quotations unless reviewed; post 3; email #2: "Preparing your family's Ramadan screen routine" (practical tips, no app pressure); a short parent survey (3 questions, no child data: what worries you about screen time, which devices, AR or EN) | Talks held; survey results (aggregate) |
| D-8 → D-1 | **Launch prep** | Posts 4–5; email #3 "launching soon" (date only once the stores have approved the app); press note to Muslim parenting outlets/podcasts; support inbox and FAQ ready; final check of claims against A1–A10 | Launch-ready kit; no unapproved claims |
| D | **Launch** (only if the gate in 2.1 is passed) | Email #4 with store links; partners get a thank-you and the parent flyer v2 with store QR | — |

### 2.6 KPIs (measurable without tracking children)

All are **aggregate, parent-side or store-provided**. None needs an SDK in the child app.

| KPI | Source | Suggested target (suggestion) |
|---|---|---|
| Confirmed waitlist sign-ups (double opt-in) | Email provider counts | 2,000 by D-1 |
| Confirmation rate (confirmed / submitted) | Email provider | ≥ 60% |
| Unsubscribe rate per email | Email provider | < 1% |
| Spam complaints | Email provider | < 0.1% |
| Partner institutions engaged (flyer or talk) | Our own outreach sheet | 15 |
| Parents' talks held / attendance (head count by host) | Host-reported number | 6 talks |
| Sign-ups per partner code (per institution, aggregate) | Waitlist DB, count only | Used to rank partners, not individuals |
| Survey responses (parents) | Survey tool, no child fields | 300 |
| Store page conversion rate, first 14 days | App Store Connect / Play Console aggregate stats | Benchmark only |
| Waitlist → install (approximation) | Email link clicks to store, counted at the redirect without per-user IDs | Benchmark only |
| Support emails and top questions | Support inbox | Feeds FAQ |
| Store rating and review themes | Stores | ≥ 4.5 average |

**Not measured, by design:** anything about the child (usage, game time, prayer completion) for marketing
purposes, any cross-site tracking, any device IDs.

---

## 3. Five social posts for parents (AR + EN)

Rules applied (STORE-LISTING section 6): no "scholar-approved/reviewed", no "COPPA certified/compliant",
no "safest/100% safe/best/#1", no "certified/halal certified", no endorsement by Quran Foundation or any
mosque, no "forever / للأبد", no prices or trial (A9), no adhan audio claim (A3 blocked), no offline claim
(A4), no app privacy/no-ads claims until A2/A7 are signed off, no lock-on-iPhone/Windows lines until A8,
no fixed Ramadan date, no Quran/hadith quotations. Every post speaks to the parent. All five are
**drafts for Quality Gate review**.

**Post 1 (concept, P1)**
- AR: لعب أطفالك يأتي بعد الصلاة والمهام، وأنت من يعتمد كل خطوة. Zad X Play تطبيق عائلي يساعدك على تنظيم وقت الشاشة بروح إسلامية: الصلاة لله، واللعب تشجيع. سجّل في قائمة الانتظار لتعرف موعد الإطلاق.
- EN: Your children's play comes after prayer and tasks, and you approve every step. Zad X Play is a family app that helps you shape screen time around Islamic habits: prayer is for Allah, and play is the encouragement. Join the waitlist to hear when we launch.

**Post 2 (parent in control, P3)**
- AR: أنت المتحكم: لوحة وليّ الأمر محمية برقم سري، والمهام والصلوات لا تُحتسب إلا بعد موافقتك، والشراء خلف رقمك السري فقط.
- EN: You stay in control: the parent area is protected by a PIN, tasks and prayers count only after you approve them, and purchases sit behind your PIN.

**Post 3 (Ramadan readiness, P2, no date, no quotations)**
- AR: رمضان على الأبواب. جرّب هذا الأسبوع قائمة مهام عائلية بسيطة: مساعدة في تحضير الإفطار، وقت قصير لقراءة القرآن معًا، ونوم مبكر قبل السحور. ما المهمة التي تبدأ بها مع أطفالك؟
- EN: Ramadan is close. This week, try a simple family task list: helping prepare iftar, a short Quran time together, an early night before suhoor. Which task will you start with your children?

**Post 4 (Quran section, P1, wording allowed by A5)**
- AR: في Zad X Play قسم للقرآن الكريم بتلاوات أربعة من كبار القرّاء، بإذن مكتوب عبر Quran Foundation. ونعمل على أن يكون مكانًا هادئًا يجلس فيه طفلك معك.
- EN: Zad X Play includes a Holy Quran section with recitations by four renowned reciters, used with written permission via Quran Foundation. We want it to be a calm place your child can sit with you.
- Gate: A5 wording only ("with permission via Quran Foundation", never "endorsed by"). Publish only once
  engineering has switched audio to the QF API (R-34).

**Post 5 (community / waitlist, P5)**
- AR: هل أنت وليّ أمر في مدرسة إسلامية أو مسجد؟ نقدّم نشرة تعريفية وجلسة قصيرة لأولياء الأمور عن تنظيم وقت الشاشة في البيت المسلم. لا نجمع أي بيانات عن الأطفال. راسلنا أو سجّل بريدك في قائمة الانتظار.
- EN: Are you a parent at an Islamic school or mosque? We offer an information sheet and a short parents' session on screen time in a Muslim home. We collect no data about children. Message us or join the waitlist with your email.
- Note: "We collect no data about children" refers to the **waitlist and outreach** (true by design,
  section 2.2). Do not reuse it as an app claim before A7 sign-off.

---

## 4. Claims in this file that need approval

| Item | Needs | Owner |
|---|---|---|
| All local prices (section 1.3) | Owner decision. Console price-point check | Owner + engineering |
| Trial length | Still open (A9). Not mentioned | Owner |
| "forever / للأبد" | Not used (A1 owner decision 2026-11-21) | — |
| Post 4 Quran line | A5 wording + R-34 done | Engineering / Quality Gate |
| Any religious text in Ramadan content | Islamic Content Reviewer | Reviewer |
| "We collect no data about children" (waitlist/outreach only) | Privacy Officer confirms waitlist setup | Privacy Officer |
| Partner names, staff Plus thank-you | Written permission, owner + legal approval | Owner / legal |
| Launch date ~1 Feb 2027 | Launch gate (2.1). Fallback after Eid | Orchestrator / Quality Gate |
| Waitlist retention period | Privacy Officer | Privacy Officer |

---

## 5. Sources

Search results gave the URLs below. Page content was not fully readable in this session, so verify each rule
in the live console or page before relying on it.

Apple
- App Store Connect Help, "Set a price": https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price
- App Store Connect Help, "Set a price for an in-app purchase": https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase
- App Store Connect API, "Configuring subscription prices across territories": https://developer.apple.com/documentation/appstoreconnectapi/configuring-subscription-prices-across-territories
- Apple Developer News, "App Store pricing upgrades have expanded to all purchase types": https://developer.apple.com/news?id=dbrszv62
- Apple Newsroom (Dec 2022), "Apple announces biggest upgrade to App Store pricing, adding 700 new price points": https://www.apple.com/newsroom/2022/12/apple-announces-biggest-upgrade-to-app-store-pricing-adding-700-new-price-points/

Google
- Play Console Help, supported locations and price ranges: https://support.google.com/googleplay/android-developer/answer/1169947
- Play Console Help, tax / VAT and tax-inclusive pricing: https://support.google.com/googleplay/android-developer/answer/138000
- Play Console Help, pricing article returned for "price ranges by country" (title not visible in results, verify): https://support.google.com/googleplay/android-developer/answer/6334373
- Google Play Help, "Tax information for Google Play purchases": https://support.google.com/googleplay/answer/2850368

Ramadan 2027 (expected dates, subject to moon sighting)
- The National (2 Sep 2026), expected Ramadan 2027 start and Eid al-Fitr in UAE: https://www.thenationalnews.com/news/uae/2026/09/02/expected-ramadan-2027-start-date-and-eid-al-fitr-holiday-dates-in-uae/
- Gulf News, "When is Ramadan 2027?": https://gulfnews.com/uae/ramadan/when-is-ramadan-2027-the-expected-date-moon-sighting-and-eid-explained-1.500630523
- Khaleej Times, likely dates for Ramadan and Eids 2027: https://www.khaleejtimes.com/uae/ramadan-eid-al-fitr-eid-al-adha-2027-likely-dates
