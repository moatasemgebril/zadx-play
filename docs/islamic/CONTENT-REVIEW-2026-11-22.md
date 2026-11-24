# Islamic content review: 2026-11-22

Reviewer: zadx-islamic-content-reviewer (AI). **This is not a scholar sign-off.** Every item below still
needs a qualified sheikh to approve it before launch. Grades are capped at B+ until that happens.

Scope: `lib/data/catalog/reading_stories.dart`, `prophets_quiz.dart`, `adhkar.dart`, `praise.dart`,
`arabic_letters.dart`, `mosque_parts.dart`, and `lib/features/edu_games/prophets/` (depiction check).

Quran text was checked against quran.com (the same Uthmani/Imlaei text as Tanzil). Hadith wording was
checked against Sahih Muslim, the Sunan collections and Hisn al-Muslim, using the reviewer's knowledge plus
the URLs already in the code.

---

## 1. reading_stories.dart (new, PR #33): Grade A- (content quality; the B+ cap applies to the overall grade)

**Checked (6 stories, 16 questions):** little_seed, shared_umbrella, broken_vase, blue_sky, new_classmate, bee_garden.

- No Quran, hadith, rulings or prophets appear. Characters who share a prophet's name (آدم، يوسف) are ordinary children,
  so no honorific is needed. This is normal Muslim naming practice.
- The themes are patience, sharing, honesty, curiosity, kindness to newcomers and caring for creation. All suit ages 5–12.
- The science is correct and simple: Rayleigh scattering explains the blue sky and the orange sunset, and bees carry pollen on their legs and pollinate flowers.
- The Arabic grammar is fine. In «كان مع آدم مظلة» and «لم يكن معه مظلة» a masculine verb comes before a feminine subject with a prepositional phrase between them, which is permitted. «فيتبعثر أكثرُ الأزرق» means "most of the blue" and is correct.
- Every answer index points to the correct option.

**Changes:** none.

**Notes (not blocking):**
- «لن تؤذيك إذا تركتها» (bee_garden) is slightly too absolute. You could soften it to «غالبًا لن تؤذيك». This is an editorial point, not an Islamic one.
- The file header says these stories "need no scholar review". I agree that they contain no religious text. Even so, the sheikh should read them once, because they ship inside an Islamic product.

## 2. prophets_quiz.dart: Grade B+

**Checked (15 questions):** Every Quran reference was checked against the meaning of the ayah. `surahAyahCounts` is correct
(2:286, 3:200, 11:123, 12:111, 19:98, 21:112, 26:227, 27:93, 34:54, 37:182, 38:88). Every prophet's name
has «عليه السلام» / "(peace be upon him)". The wrong answers are neutral.

**Changes:**

| id | Before | After | Why / source |
|---|---|---|---|
| yunus_whale (question) | «ماذا التقم يونس عليه السلام في البحر؟» | «ما الذي التقمَ يونسَ عليه السلام في البحر؟» | Grammar. Without harakat the old text reads "What did Yunus swallow?", which is the wrong way round. The whale is the subject: «فَالْتَقَمَهُ الْحُوتُ وَهُوَ مُلِيمٌ». https://quran.com/saffat/142 |
| sulaiman_ant (fact) | «قالت نملة للنمل: ادخلوا بيوتكم حتى لا يحطمكم سليمان عليه السلام وجنوده…» | «حذّرت نملةٌ النملَ وطلبت منهم أن يدخلوا مساكنهم حتى لا يحطمهم سليمان عليه السلام وجنوده وهم لا يشعرون، فتبسّم سليمان عليه السلام ضاحكًا من قولها.» | The old text was presented as a direct quote but changed the ayah's wording (the ayah says «ادْخُلُوا مَسَاكِنَكُمْ», not «بيوتكم»), so children could memorise a wrong version. It is now indirect narration. https://quran.com/27/18-19 |
| sulaiman_hoopoe (fact) | «تفقّد سليمان عليه السلام الطير، فسأل: لماذا لا أرى الهدهد؟» | «تفقّد سليمان عليه السلام الطير، فلم يرَ الهدهد بينها، فسأل عنه.» | The old text put reworded direct speech in a prophet's mouth (the ayah says «مَا لِيَ لَا أَرَى الْهُدْهُدَ»). It is now neutral narration. The English was already indirect and is unchanged. https://quran.com/27:20 |

The honorific regex in `test/edu_games_test.dart` allows harakat after a name, so «يونسَ عليه السلام» still passes. No test references the changed strings.

**Flagged for the sheikh:**
1. adam_names: «آدم عليه السلام هو أول إنسان». This is established belief, but 2:30–31 does not say "first human" in those words. Should we keep this wording and reference?
2. adam_names answer: «أسماء الأشياء كلها» follows the Ibn Abbas tafsir of «الأسماء كلها». Is this acceptable for children?
3. yunus_whale: the English answer is "A big fish (a whale)". Is it acceptable to translate الحوت as "whale"?
4. isa_cradle: «وقال إنه عبد الله» is an indirect paraphrase of 19:30. Please confirm.
5. sulaiman_ant and sulaiman_hoopoe: please confirm the new indirect narration shown above.
6. Keep `reviewedByScholar` as `false` until the sheikh signs off.

## 3. adhkar.dart: Grade B

**Checked (15 items + 2 reminders):** texts and counts.

| id | Count | Check |
|---|---|---|
| m_asbahna / e_amsayna | 1 | Muslim 2723 wording; morning form as in Hisn al-Muslim. OK |
| m_bika / e_bika | 1 | Tirmidhi 3391 («النشور» in the morning, «المصير» in the evening). OK |
| m_bismillah / e_bismillah | 3 | Abu Dawud 5088, Tirmidhi 3388. OK |
| m_radeetu | 3 | Hisn 87. Text OK (ﷺ shown as a note) |
| m_hasbi / e_hasbi | 7 | Abu Dawud 5081. Text OK |
| m_subhan / e_subhan | 100 | Muslim 2692. OK |
| e_kalimat | 3 | Hisn 97 (also Muslim 2709). OK |
| s_ibrahimiya | 1 | Bukhari 3370. OK |
| qulsReminder | 3 | Abu Dawud 5082. OK |

**Changes:** none.

**Flagged for the sheikh:**
1. m_radeetu (×3): scholars differ on its grading. Al-Albani graded the Abu Dawud 5072 and Tirmidhi 3389 chains as weak; others graded it hasan. Abu Dawud's wording also has «رسولًا» where the app has «نبيًّا». Should we keep it, and which wording should we use?
2. m_hasbi / e_hasbi (×7): Abu Dawud 5081 is mawquf (stops at Abu ad-Darda'), and al-Albani graded the marfu' version (attributed to the Prophet ﷺ) as weak. The app makes no reward claim. Should we keep it?
3. m_asbahna / e_amsayna have no harakat, unlike every other item. I did not add harakat myself. Please approve a vocalised text from the cited page.

**Notes:**
- The owner decided on 2026-11-22 to rely on "trusted published sources instead of a sheikh sign-off". The reviewer still recommends that a qualified sheikh sign off on the adhkar before launch.
- The "Verified counts" doc comment leaves out radeetu (3) and kalimat (3). This is cosmetic, so I did not change it.

## 4. praise.dart: Grade B+

**Checked:** 6 Islamic phrases and 6 neutral phrases (Kids build). Gender agreement is correct (أحسنتَ/أحسنتِ، فيكَ/فيكِ، حسناتكِ، كمِّل/كمِّلي).
There is no Quran or hadith. «تبارك الله» is correctly said of Allah, not of the child.

**Changes:** none.

**Flagged for the sheikh:**
1. «جزاك الله خيرًا» is a thank-you for a favour. Is it suitable as general praise? (Carried over from the 2026-11-20 review.)
2. «كمِّل كده» is Egyptian dialect inside a phrase that is otherwise fusha and religious. Is the tone acceptable? (Editorial.)

## 5. arabic_letters.dart: Grade A- (no religious content)

All 28 letters are in the standard hijā'ī order (…ن ه و ي) and have correct names. The six non-joining letters (ا د ذ ر ز و) are correct.
The look-alike groups are correct. **Changes:** none. Hamza (ء) and لا are not included, which is a curriculum choice rather than an error.

## 6. mosque_parts.dart: Grade A- (content quality; the B+ cap applies to the overall grade)

All 10 lines are accurate and respectful, with no Quran or hadith. «المسجد بيت من بيوت الله» and «الشهور الهجرية تبدأ مع ظهور الهلال الجديد» are correct.
**Changes:** none. **Optional suggestion for the sheikh:** the door line could also teach entering with the right foot and saying the entry dua. Any dua added must come from a verified source.

## 7. lib/features/edu_games/prophets/: Pass

`scene_painter.dart` draws only scenery and objects: sky, sea, the Ark, the Kaaba, flames and flowers, a well, stars, the sun and moon, armour, and the animals named in the Quran (whale, ant, hoopoe, camel).
No human figures, faces or silhouettes are drawn. `prophets_game_screen.dart` uses only Material icons (arrow, play, book).

---

## Overall Islamic-content grade: B+ (up from C+)

B+ is the cap: an A needs sign-off from a qualified sheikh.

**Flagged for the sheikh: 11 questions** (prophets_quiz 6, adhkar 3, praise 2).

Before launch, a sheikh must sign off on all six catalogs. Set `reviewedByScholar = true` only after that sign-off.
