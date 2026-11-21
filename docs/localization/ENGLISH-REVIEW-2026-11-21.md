# English localization review (2026-11-21)

Branch `fix/english-review`. Reviewer: zadx-localization-rtl. Style rules: [ENGLISH-STYLE-GUIDE.md](ENGLISH-STYLE-GUIDE.md).

## The adhkar title issue the owner reported
In the Quran tab, the Adhkar view has three section chips: Morning adhkar / Evening adhkar / salawat. The third chip read **"Salawat on the Prophet ﷺ"**. This is a word-for-word copy of «الصلاة على النبي ﷺ»:
- "on" copies the Arabic «على».
- "Salawat" is left untranslated, so English-speaking kids read it as "prayers" (salah), not as sending blessings on the Prophet ﷺ.

The fix is **"Blessings on the Prophet ﷺ"**. This is the usual plain-English wording and it keeps the ﷺ honorific.

Other problems on the same screen:
- The completion banner and toast read "Masha'Allah! Adhkar done and sent for approval". This is telegraphic and also a word-for-word copy. Fixed (see the table below).
- The counter showed **"0 / 1 times"** for adhkar said once. The Arabic had the same problem («١ مرات»). Fixed in `adhkar_view.dart`: when the count is 1, only the number is shown. No Arabic text was changed.
- The hadith source («مسلم», «الترمذي» …) was shown in Arabic, right-to-left, inside the English UI. It now shows in English (Muslim, At-Tirmidhi, Abu Dawud, Al-Bukhari, At-Tabarani) through `Dhikr.sourceOf(lang)`. The Arabic UI is unchanged.

If the owner's screenshot shows a different string, please send it and it will be fixed in this PR.

## Changes (old → new, reason)

### lib/l10n/app_en.arb (29 values; no keys or placeholders changed)
| Key | Old | New | Reason |
|---|---|---|---|
| salawat | Salawat on the Prophet ﷺ | Blessings on the Prophet ﷺ | Word-for-word copy of the Arabic; unclear term (owner's report) |
| sectionDone | Masha'Allah! Adhkar done and sent for approval | MashaAllah! You finished your adhkar. Sent to your parent for approval. | Telegraphic, copies the Arabic; transliteration |
| played | Played | Time played | Matches "Time earned" |
| zadGameLetters | Quran letters | Quran Letters | Game name, and other strings already capitalize it |
| zadGameProphets | Prophet heroes | Prophet Heroes | Same |
| zadGameMasjid | Build your masjid | Build Your Masjid | Same |
| deviceGamesNote | Open after tasks, … | Unlock after tasks, … | Clearer verb |
| gamesCount | …kids games | …kids' games | Apostrophe |
| psNotifyAdhan | …if playing | …if my child is playing | Unclear subject |
| psAlertAdhan | pause it from PlayStation Family | pause play in PlayStation Family | Unclear "it"; preposition |
| msAlertAdhan | pause it from Microsoft Family Safety | pause play in Microsoft Family Safety | Same |
| consolesNote | don't allow other apps to lock them … you allow or pause play from the official app in one tap | don't let … you can allow or pause play in the official app with one tap | Fluency |
| pairDone | Device linked to the family | Device linked to your family | Natural wording |
| lockAtAdhan | Lock games at adhan | Lock games at the adhan | Missing article |
| asrStandard | Standard (Shafi) | Standard (Shafi'i) | Correct transliteration |
| soon | Soon | Coming soon | Correct label wording |
| assistantHello | I am | I'm | Friendlier tone |
| how1T | Set country & language | Set your country and language | Natural wording |
| how2T | Set the tasks | Set up tasks | Natural wording |
| how3B | They tap "Done" and you get it right away. | They tap "Done" on the Tasks page and you're notified right away. | Unclear "it"; matches the Arabic |
| faq3A | the method is set… | the calculation method is set… | Clarity |
| startTrial | Start 14-day free trial | Start your 14-day free trial | Natural wording |
| featKids | Children | Number of children | Matches «عدد الأطفال» |
| childNicknameInvalid | e-mail | email | Spelling |
| eduLevelLocked | Finish the level before to open this one | Finish the previous level to unlock this one | Ungrammatical |
| eduRoundDone | Masha'Allah! Round complete | MashaAllah! Round complete! | Transliteration |
| mosqueNeedStars | You need {n} more stars. … to earn some! | Not enough stars yet: {n} to go. … to earn more! | "1 more stars" bug, no ICU needed |
| mosqueComplete | Masha'Allah! Your masjid is complete | MashaAllah! Your masjid is complete! | Transliteration |
| recitationComingSoon | in sha Allah | InshaAllah | Transliteration |

### Catalogs and Dart
| File | Old | New | Reason |
|---|---|---|---|
| data/catalog/praise.dart | Masha'Allah, well done! | MashaAllah, well done! | Transliteration |
| data/catalog/praise.dart | Masha'Allah, blessed is Allah! Keep it up! | MashaAllah, blessed is Allah! Keep it up! | Transliteration |
| data/catalog/prophets_quiz.dart | What did Allah make the fire for Ibrahim (pbuh)? | What did Allah make the fire become for Ibrahim (pbuh)? | Ambiguous (could read as "why"); meaning unchanged |
| data/catalog/default_tasks.dart | Memorize Surat Al-Falaq | Memorize Surah Al-Falaq | Same "Surah" spelling everywhere |
| data/catalog/games.dart | Ludo with family | Ludo with the family | Article |
| data/catalog/locations.dart | Tripoli (LB) | Tripoli (Lebanon) | Code not clear to kids |
| data/catalog/adhkar.dart + features/adhkar/adhkar_view.dart | Arabic source in the English UI; "0 / 1 times" | English source names; "0 / 1" | Bidi and plural |
| features/home/home_screen.dart | "Cairo، Egypt" (hard-coded Arabic comma) | "Cairo, Egypt" in English | Punctuation and bidi |

Total: 29 .arb values, 6 catalog strings, 3 Dart display fixes.

## For zadx-islamic-content-reviewer
1. `salawat`: please confirm "Blessings on the Prophet ﷺ" for «الصلاة على النبي ﷺ». The alternative is "Salawat upon the Prophet ﷺ".
2. `qulsReminder` (adhkar.dart): "Recite Al-Ikhlas, Al-Falaq and An-Nas 3 times". Should it say "3 times each"? Left unchanged on purpose.
3. praise.dart: "MashaAllah, blessed is Allah!" for «ما شاء الله تبارك الله». Should it be "MashaAllah, TabarakAllah!"? Also "May Allah reward you with good!" for «جزاك الله خيرًا»: the usual wording is "May Allah reward you with goodness". Left for the reviewer.
4. prophets_quiz.dart: the wording of `ibrahim_fire` was changed (meaning kept). "Cool and safe" is used for «بردًا وسلامًا».
5. English names of the hadith sources (`dhikrSourcesEn`).

## Open items (not changed)
- `inviteShareText`: the Arabic adds «علشان تاخد خصم» ("to get a discount"). The English has no discount promise. This needs owner or marketing confirmation that a referee discount exists before adding it.
- Plurals: `childLimitBody` ("up to {max} children" when max=1), `ayatCount`, `rewardMonths` and `dhikrTimes` use String placeholders. Real ICU plurals need numeric types in app_ar.arb and Arabic plural forms (Arabic «١٠٠ مرات» should be «١٠٠ مرة»). This is an Arabic copy change, so it is out of scope here.
- `exCountOne` "Count one {name}": the context is unclear. It needs a screen check.
- `pairOffline` "Linking requires Firebase to be configured." is developer wording shown to users, in both languages.
- Hard-coded English in other `lib/**/*.dart` files was not fully swept. The review tools could not list or search directories, so only the files that were opened were checked.
