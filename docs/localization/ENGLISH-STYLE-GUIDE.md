# Zad X Play: English style guide

Readers are Muslim parents and children aged 5 to 12 in English-speaking countries. Arabic is the primary language. English must read naturally and must not sound like a word-for-word translation of the Arabic.

## Voice
- Use short, warm, simple sentences. Talk to the child as "you". Talk to parents about "your child".
- Use contractions ("you're", "don't", "I'm").
- Use exclamation marks only for praise and celebration.
- Spelling: Oxford British (colour, licence, armour) with -ize endings (memorize). Use "email", not "e-mail".

## Capitalization
- Use sentence case for titles, buttons and labels ("Morning adhkar", "Parent dashboard").
- Use Title Case only for product and game names: Zad X, Zad X Plus, Quran Letters, Prophet Heroes, Build Your Masjid.
- Always capitalize: Allah, Quran, Prophet (meaning Muhammad ﷺ), prayer names (Fajr, Dhuhr, Asr, Maghrib, Isha), surah names, Ramadan, Kaaba.
- Lower-case Islamic common nouns: adhan, adhkar, dhikr, wudu, masjid, surah (inside a sentence), muezzin, salam.

## Transliteration (one style only)
| Term | Use | Do not use |
|---|---|---|
| ما شاء الله | MashaAllah | Masha'Allah, Mashallah |
| إن شاء الله | InshaAllah | in sha Allah, Inshallah |
| السلام عليكم | Assalamu alaikum | Assalamualaikum |
| أذكار / ذكر | adhkar / dhikr | azkar, athkar |
| أذان | adhan | azan, athan |
| وضوء | wudu | wudhu |
| مسجد | masjid ("mosque" is fine in running text) | |
| سورة | Surah Al-Falaq | Surat Al-Falaq, Sura |
| جزء | Juz Amma, Juz Tabarak | |
| شافعي | Shafi'i | Shafi |
- Surah names use the hyphenated article: Al-Fatiha, An-Nas, Ash-Shams.
- Use "prayer" in UI text. Keep "salah" out of buttons.

## Honorifics
- Prophet Muhammad: put "ﷺ" right after the reference ("the Prophet ﷺ"). Do not write "(PBUH)".
- Other prophets: "(peace be upon him)" after each name. A test checks this in the Prophet Heroes game.

## Religious text
- Never translate or rewrite Quran, hadith or dhikr wording yourself. Use well-known translations (for example, Hisn al-Muslim in English) and flag any doubt to zadx-islamic-content-reviewer.
- Arabic dhikr is always shown in Arabic, in every language.

## Numbers and plurals
- If a count can be 1, avoid "{n} times / {n} stars" unless the placeholder is an ICU plural. Either rephrase ("{n} to go") or use ICU `{n, plural, =1{…} other{…}}`. ICU needs a numeric placeholder type in app_ar.arb (the template).
- Use Arabic punctuation (، ؛ ؟) only in Arabic strings. Never hard-code it in Dart that also runs in English.

## Length
- Tabs and chips are about 110 px wide at 16–17 px. Keep labels to about 3 words. Put longer text in notes.

## Process
- Edit `app_en.arb` value by value. Never rename keys or placeholders. New keys go in `app_ar.arb` (template) first.
