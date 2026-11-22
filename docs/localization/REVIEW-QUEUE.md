# Localization review queue

Strings that engineering must **not** change on its own. Each item needs a named reviewer's
decision before the text changes. Opened 2026-11-22 by zadx-bug-fixer (branch
`fix/child-safety-and-language`). Keys refer to `lib/l10n/app_ar.arb` (template) and `app_en.arb`.

## A. Islamic Content Reviewer (religious rulings / wording) — not changed

| # | Key / topic | Current text | Question for the reviewer |
|---|---|---|---|
| A1 | `prayerSub` | ar «قوم اتوضى وصلّي، وبعدها اضغط الزرار» · en "Make wudu and pray, then tap the button" | Is the instruction wording right for children of all ages? Should it say "if you don't already have wudu" (a child who still has wudu does not need to renew it)? |
| A2 | `asrStandard` | ar «الجمهور (شافعي)» · en "Standard (Shafi'i)" | The standard (shadow = 1×) Asr time is also the Maliki and Hanbali position. Should the label read e.g. «الجمهور (شافعي، مالكي، حنبلي)» / "Standard (Shafi'i, Maliki, Hanbali)"? North-African (Maliki) families may think their school is missing. |
| A3 | Warsh for the Maghreb | Reciters offered today are all Hafs ʿan ʿĀṣim (`lib/data/catalog/quran.dart`). | Children in Morocco, Algeria and parts of Tunisia/Libya/West Africa learn the Warsh ʿan Nāfiʿ reading. Should we offer a licensed Warsh recitation (and Warsh Mushaf text) for those countries? Needs a licensed source (Quran Foundation approval covers 4 Hafs reciters only). |
| A4 | Girls excused from prayer (design note only) | Not built. | Proposal: a quiet, parent-controlled "excused today" option in the parent area (behind the PIN) that pauses the prayer task and prayer lock for a girl on the days she is excused, with no label or reason ever shown to the child, siblings or the family sync log. Please confirm the ruling summary, the wording, and whether it should be per prayer or per day. No code until approved. |
| A5 | Quran font | Quran verses and adhan phrases currently render in the platform Arabic font (Amiri Quran is no longer downloaded at runtime; files to be bundled, see docs/FONTS.md). | Please check a few surahs on Android and iPhone for missing or misplaced marks (waqf signs, small high letters) until Amiri Quran is bundled. |
| A6 | `featQuran` | ar «القرآن الكريم (القرّاء المتاحين)» · en "Quran (available reciters)" | Neutral wording (no "approved", no "licensed"): the Quality Gate (2026-11-22) asked that we not claim licensing while audio still streams from everyayah.com. Once audio moves to the Quran Foundation recitations API and the licence is confirmed (pre-launch blocker, BACKLOG "Quran Foundation approval"), the reviewer may approve «تلاوات مرخّصة عبر Quran Foundation» / "Licensed recitations via Quran Foundation". |

## B. Legal / privacy review — text changed, sign-off required before release

`lockDisclosureBody` and `protectAdminDisclosureBody` (Arabic) were rewritten from Egyptian
colloquial into clear, simplified Modern Standard Arabic with the **same meaning** (no new claims,
nothing removed). These are the prominent disclosures Google Play requires before the
Accessibility service and Device Admin are turned on, so **legal review is required** before
release: check that the Arabic and English still say exactly the same thing and match the privacy
policy and the Play Console declarations.

Note for design: the titles and buttons of these two dialogs are still colloquial
(«قبل ما نفعّل القفل», «موافق، كمّل»). Decide whether to keep the mix or move the whole dialog to MSA.

## C. Follow-ups (not in this PR)

- Other number placeholders that are still `String` because they need no noun agreement
  ("level {n}", "{done} of {total}", "stars: {n}"). Candidates for ICU plurals later:
  `minsPlus` («+{n} دقيقة»), `deviceLockFreePrayerNote` («{n} دقيقة»), `gamesCount`, `mosqueNeedStars`.
