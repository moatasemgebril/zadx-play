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

## A′. Resolved 2026-11-22 (owner decision: verified official/trusted sources instead of a sheikh sign-off)

| # | Decision | Source |
|---|---|---|
| A1 | `prayerSub` is now gender-aware (ICU select on the child's form of address; unset = masculine form): «توضّأ إن لم تكن على وضوء، ثم صلِّ، واضغط الزر بعدها» / «توضّئي إن لم تكوني على وضوء، ثم صلّي، واضغطي الزر بعدها» · en "Make wudu if you need to, pray, then tap the button". | Renewing wudu is not required for someone who still has it (owner's verified decisions report, 2026-11-22). |
| A2 | `asrStandard` «الجمهور (المالكي والشافعي والحنبلي)» / "Majority (Maliki, Shafi'i, Hanbali)"; `asrHanafi` «الحنفي (ظلّ المِثلين)» / "Hanafi (shadow ×2)". | Owner's verified decisions report, 2026-11-22. |
| A4 | "Excused" (menstruation) option: parent-only, per day, per child, no reason shown to the child or siblings. Implemented in PR #35 (`test/prayer-times-world`). | Dar al-Ifta al-Misriyya fatwa 7711 (https://dar-alifta.org/ar/fatwa/details/19049/); Ibn Baz fatwa 13476. |
| Adhkar | `m_radeetu`: «رضيت بالله ربا، وبالإسلام دينا، وبمحمد نبيا» without «صلى الله عليه وسلم» inside the recited text (ﷺ shown as a note); source «الترمذي وغيره». `e_kalimat`: source «الترمذي». `s_short` ("ten salawat in the morning", At-Tabarani) removed: weak (al-Albani, Silsila ad-Da'ifa 5788); replaced by a count-free reminder «أكثِروا من الصلاة على النبي ﷺ». Counts verified: bismillah 3, hasbi 7, subhan 100, bika 1, ibrahimiya 1. | https://sunnah.com/hisn:87 · https://sunnah.com/hisn:97 |
| Adhkar (resolved 2026-11-22) | `e_amsayna` (evening, ×1) now has the full narration of Ibn Mas'ud: «أمسينا وأمسى الملك لله، … ربِّ أسألك خير ما في هذه الليلة وخير ما بعدها، وأعوذ بك من شر ما في هذه الليلة وشر ما بعدها، رب أعوذ بك من الكسل، وسوء الكبر، رب أعوذ بك من عذاب في النار، وعذاب في القبر». `m_asbahna` (morning, ×1) uses the same text with «أصبحنا وأصبح الملك لله» and «هذا اليوم … ما بعده», per the hadith «وإذا أصبح قال ذلك أيضا: أصبحنا وأصبح الملك لله» and hadeethenc's explanation (the day replaces the night, pronouns adjusted). Source «رواه مسلم (2723)». Exact texts locked in `test/adhkar_catalog_test.dart`. | https://sunnah.com/muslim:2723a · https://hadeethenc.com/ar/browse/hadith/3008 |
| Letters | `lettersLevel3` «حروف الهجاء الثمانية والعشرون كلها». | Owner's verified decisions report, 2026-11-22. |
| Riwaya | The Quran screen shows «رواية حفص عن عاصم» / "Hafs from 'Asim" above the reciter choice. | All offered reciters are Hafs (`lib/data/catalog/quran.dart`). |
| Ikhlas | After a prayer task: «الصلاة لله، والجائزة تشجيعٌ لك» / "Prayer is for Allah; the reward is just encouragement." (no emoji). | Owner's verified decisions report, 2026-11-22. |

Still open in section A: **A3 Warsh** (P2, must be done before any Maghreb launch), A5 (Quran font check), A6 (`featQuran` wording until the licence is confirmed).

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
