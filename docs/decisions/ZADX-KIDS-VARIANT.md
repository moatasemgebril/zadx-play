# Decision: "Zad X Kids", a non-religious app built from the same codebase

Status: **Proposed** (zadx-cto-architect, 2026-11-22; market + artwork update by zadx-kids-art-director, 2026-11-22). Owner decisions of 2026-11-22. Needs Security review, QA, the Quality Gate and the owner's sign-off on the open decisions in section 8.
Branch: `feat/zadx-kids-variant`.

## ملخص بالعربي

**القرار:** نعمل تطبيق تاني اسمه **Zad X Kids** من نفس الكود (نفس براند Zad X)، بمعرّف متجر منفصل `com.zadx.kids` وقائمة منفصلة في المتاجر، ومن غير **أي** محتوى ديني: مفيش قرآن ولا تلاوة ولا مواقيت صلاة ولا أذان ولا أذكار ولا عبارات زي "ما شاء الله"، ولا لعبة المسجد ولا لعبة الأنبياء، ولا هلال أو مسجد في الرسومات.

**بدل قفل الصلاة** فيه 3 مواعيد قفل يحددها ولي الأمر: **وقت المذاكرة**، **وقت النوم** (بيقفل بالليل ويفتح الصبح)، و**وقت القراية** كل يوم. القفل ده بيشتغل على أندرويد حتى لو التطبيق مقفول.

**الباقة المجانية في Kids:** قفل الجهاز بالمواعيد + حد يومي لطفل واحد. الباقات المدفوعة (أساسي وبلس) زي ما هي، بأكواد منتجات منفصلة (`zadx_kids_basic_monthly` …) والسيرفر بيتحقق منها بنفس الصرامة.

**كلمات التشجيع** بقت محايدة ومناسبة لولد أو بنت: "أحسنتَ! / أحسنتِ!"، "برافو عليك! / عليكِ!" …

**تحديث 22-11-2026 (السوق المستهدف):** Zad X Kids موجّه لأمريكا وأوروبا والسوق الغربي. يعني:
- اللغة الافتراضية **الإنجليزي** من أول تشغيل (العربي اختياري من الإعدادات).
- **مفيش أي كتابة عربية** في أي رسمة أو خلفية أو لوجو أو أيقونة في Kids.
- **مفيش مسجد ولا قبة ولا مئذنة ولا هلال ولا فانوس ولا كعبة ولا سجادة صلاة ولا النجمة الثمانية** في أي رسمة. بدل المسجد في الصفحة الرئيسية فيه **شجرة كبيرة عليها بيت شجرة** وسلّم حبل ومرجيحة، والسماء الليلية بقت **فضاء** (قمر بدر، كوكب بحلقة، صاروخ صغير)، وخلفية ولي الأمر نقط ومربعات ناعمة.
- **لعبة الحروف العربية اتشالت من Kids** (فاضلة في Zad X Play).
- اختبارات بتمنع أي حرف عربي أو رسمة دينية ترجع تاني.

**مطلوب من صاحب المشروع:** لوجو وأيقونة محايدة لـ Kids (اللوجو الحالي فيه هلال ومساجد)، الموافقة على المواعيد الافتراضية، وقرارات المتاجر والخصوصية في القسم 8.

---

## 0. Target market and artwork rules (owner decision 2026-11-22)

**Zad X Kids is for the US, Europe and the wider Western market.** Zad X Play stays the app for Muslim families. On top of "nothing religious", Zad X Kids follows these rules:

1. **English first.** A fresh install starts in English (`defaultLanguageFor(AppVariant.kids, …) == 'en'`, whatever the phone language). Arabic stays available as an optional UI language in Settings, because it costs nothing to keep. The "coming soon" languages are Español, Français and Deutsch.
2. **No Arabic script in any artwork**: no Arabic writing, calligraphy or Arabic-letter decoration in scenes, painters, icons, the logo/wordmark or the splash. The Zad X Play artwork logo (Arabic lettering, crescent, mosques) is never used: `BrandLogo` draws a Latin "ZAD X KIDS" wordmark in the Kids palette (teal `#0F766E`/`#134E4A`, sun yellow `#FFD23F`, coral `#FF8A65`). This holds even when the parent picks Arabic as the UI language.
3. **No religious architecture or symbols in artwork**: no mosque, dome, minaret, crescent, lantern, Kaaba, prayer mat or eight-point Islamic star pattern. One compile-time flag, `artReligiousMotifs` (lib/shared/art/art_shapes.dart, `!kIsKids`), is the default of every painter, so the Kids build always takes the neutral branch:

   | Scene / icon | Zad X Play | Zad X Kids |
   |---|---|---|
   | Home (sunrise town) | mosque with dome, minaret, crescents | **big oak with a treehouse**, rope ladder, tyre swing and a plain pennant |
   | Night sky (Quran area; never shown in Kids) | crescent, lanterns, domes, star lattice | **space**: full moon with craters, ringed planet, pine hills, cosy houses, a rocket drifting by |
   | Prayer sky strip (never shown in Kids) | crescent at night, dome on the hill | full moon, little pitched-roof house |
   | Parent / settings / help / plans | faint eight-point-star lattice | rounded squares and dots |
   | `ZadIconKind.prayer` / `.quran` (never shown in Kids) | dome + crescent / book on a stand | alarm clock / open storybook |
   | Bedtime schedule icon | — | a bed (`Icons.bed_rounded`), not a crescent moon |
   | "Moon" child avatar | crescent icon | a planet, labelled "Planet" / "كوكب" |
   | Games islands, tasks garden, celebrations | unchanged (already neutral) | unchanged |

   Every Kids scene keeps the same quality bar: same palette contract (text ≥ 4.5:1 under the scrim), `RepaintBoundary` per layer, seamless loops, a still frame with reduce-motion, no flashing.
4. **No Arabic Letters game.** It teaches Arabic-language content, so it is Zad X Play only (`playOnlyZadGameIds`, `Routes.playOnly`). Zad X Kids has no built-in learning game for now: the Games tab hides the "Zad X games" section and the plan cards do not list "learning games". A neutral learning game (e.g. English phonics or numbers) can be added later.

`ArtShapes.crescent`, `.dome` and `.eightPointStar` assert `artReligiousMotifs` and count every call (`ArtShapes.debugReligiousMotifCount`), so painting one in a Kids test fails.

## 1. How the variant is chosen

One constant, fixed at **compile time**:

```dart
// lib/core/app_variant.dart
enum AppVariant { islamic, kids }
const bool kIsKids = String.fromEnvironment('ZADX_VARIANT') == 'kids';
const AppVariant appVariant = kIsKids ? AppVariant.kids : AppVariant.islamic;
```

* Default (no define) = **Zad X Play**, exactly as before.
* `--dart-define=ZADX_VARIANT=kids` = **Zad X Kids**.

Why a dart-define and not a second `main_kids.dart` or Android `productFlavors`:

* A Dart entry point cannot set a `const`; only `--dart-define` gives a compile-time constant, and only a compile-time constant lets the compiler **remove** the Islamic code from the Kids binary (`if (!kIsKids)` branches are eliminated before tree-shaking).
* CI generates the Android project with `flutter create` on every run (`android/` only holds our native files). `productFlavors` would also force `--flavor` on every build and rename the existing `zadx-android-apk` artifact. Instead `android/scripts/integrate_native.py --variant kids` patches the generated shell: `applicationId com.zadx.kids` (the Kotlin namespace stays `com.zadx.app`), label "Zad X Kids", neutral Accessibility text, no adhan sound.

## 2. What is in / out

| Area | Zad X Play | Zad X Kids |
|---|---|---|
| Store name / app id | Zad X Play, `com.zadx.app` | **Zad X Kids**, `com.zadx.kids` (Android + iOS bundle id) |
| Tabs | Home, Games, Quran, Tasks, Parent | Home, Games, Tasks, Parent |
| Routes | + `/quran`, `/edu/prophets`, `/edu/masjid`, `/edu/letters` | **no route** to them (not built); a link to one redirects to Home |
| Home | prayer times card, adhan card, mosque in the town scene | today's schedule card, the same town with a treehouse oak instead of the mosque, sun instead of crescent |
| Locks | prayer lock at each adhan ("I prayed") + tasks + daily limit | **study / bedtime / reading schedules** + tasks + daily limit |
| Notifications | adhan notifications (local), "adhan" push to parent | none of them (the adhan notification service is never initialised) |
| Background | native prayer alarms (`schedulePrayerLocks`) | schedules evaluated natively on every window change (Android) |
| Learning games | Quran Letters, Prophet Heroes, Build Your Masjid | **none for now** (Arabic Letters removed for the Western market; section hidden) |
| Starter tasks | prayer, homework, Surah memorisation, adhkar, room, exercises | homework, room, exercises (+ the shared reading task when it lands) |
| Praise after a task | Islamic phrases (pending sheikh review) | neutral, gender-aware Arabic (أحسنتَ/أحسنتِ …) |
| Settings | language, country, city, calculation method, Asr | language (**English by default**, Arabic optional) + "link this device" |
| Parent area | + adhan switches, play windows between prayers, Windows Guard | + **Schedules** card; no adhan switches, no Windows Guard yet |
| Plans | Free = lock + prayer times + adhan + Quran + adhkar | Free = lock with schedules + daily limit (1 child); Basic/Plus unchanged |
| Products | `zadx_basic_monthly` … | `zadx_kids_basic_monthly`, `zadx_kids_basic_yearly`, `zadx_kids_plus_monthly`, `zadx_kids_plus_yearly` |
| Assistant | Islamic-family prompt | prompt with no religious content (`KIDS_ASSISTANT_PROMPT`) |
| Logo | artwork logo (Arabic lettering, crescent, mosques, "Islamic Values") | drawn Latin "ZAD X KIDS" wordmark (`BrandLogo`, teal / sun / coral), no watermark |
| Artwork | mosque, crescent, lanterns, eight-point star | treehouse, full moon, planets, dot grid: **no religious motif, no Arabic script** (section 0) |
| Bundled assets | adhan MP3, logo | removed before the build (`tools/kids_variant_prepare.py`) |

Reading is in both apps: the reading task / paper-book timer (branch `feat/splash-and-reading`) needs no variant switch. Anything that shows a logo (e.g. the new splash screen) must use `BrandLogo`, never `assets/images/zadx_logo.jpg` directly.

## 3. How it works in the code

* **Strings.** The ARB files stay the Zad X Play text. In Kids, `KidsLocalizationsDelegate` (lib/variant/kids_localizations.dart) returns subclasses of the generated `AppLocalizationsAr/En` that override:
  * `kidsRewrites` — 21 shared strings rewritten in neutral words (greeting, help/FAQ, lock texts, plan text, Accessibility disclosure…);
  * `islamicOnlyL10nKeys` — 66 strings used only by Islamic screens; they return `''` as a second safety net.
  Kids-only text (schedules, wordmark) lives in `KidsText` (lib/variant/kids_strings.dart).
* **Plans.** `featuresOf(tier, variant:)` / `hasFeature(…, variant:)` drop `islamicOnlyFeatures` (`prayerTimes`, `adhan`, `quran`, `adhkar`) in Kids. The `AppFeature` enum and the backend `PLAN_FEATURES` mirror are unchanged.
* **Routes.** `appRoutes()` / `shellTabsFor()` in lib/router.dart add the Islamic routes only behind `!kIsKids && variant == islamic`.
* **Schedules.** lib/features/schedule/: `ScheduledLock` (kind, start/end minute, weekdays, crosses midnight), `activeScheduledLock` (bedtime > study > reading), `ScheduleController` (on-device, PIN-protected parent card). `lockStateFor(schedule:)` locks with reason `bedtime|study|reading`; `LockPolicy` carries the enabled windows plus `baseLocked/baseReason` (the state without schedules).
* **Android native.** `LockRules.activeSchedule` (mirror of the Dart rule, unit-tested in `LockRulesTest`) is checked by `LockStore.shouldBlock()` on every window change, so bedtime starts and ends on time even when Zad X is closed. The block screen has neutral texts for the three kinds.
* **Backend.** security.ts `PRODUCTS` now lists both apps' product ids with `{tier, app}`. `verifyPurchase` looks the token up with **that app's** Play package and only accepts a Google line item whose product belongs to the same app (`verifiedLine`); the tier still comes from Google, never from the client. `storeApp` is stored in the server-only `private/billing` doc so referral deferrals use the right package/product (no Firestore rule change). `playNotifications` only handles our two package names. Firestore rules are unchanged.

## 4. Build and run

```sh
# Zad X Play (unchanged)
flutter run
flutter test

# Zad X Kids
flutter run --dart-define=ZADX_VARIANT=kids
flutter test --dart-define=ZADX_VARIANT=kids test/kids_variant_test.dart test/kids_artwork_test.dart test/schedule_test.dart

# Zad X Kids APK (CI or a throw-away clone: the first step deletes the Islamic assets)
python3 tools/kids_variant_prepare.py --apply
python3 android/scripts/integrate_native.py --variant kids
flutter build apk --debug --dart-define=ZADX_VARIANT=kids
```

CI (`.github/workflows/zadx-ci.yml`, light PR job): after the Zad X Play steps it runs the Kids tests with the define, builds the Kids APK, checks its package name / label and that no adhan or logo file is inside, and uploads it as **`zadx-kids-android-apk`**. `zadx-android-apk` is still the Zad X Play APK. The Kids build is incremental on the same runner.

## 5. Guard rails (tests)

* `test/kids_variant_test.dart` — runs in both builds:
  * every string the Kids build can show (ARB + rewrites − Islamic-only), the Kids brand/store text, praise, starter tasks and schedule texts contain **none** of the words in `tools/kids_forbidden_words.json` (Arabic + English, the only copy of the list);
  * every rewritten / Islamic-only key has an override; placeholders match;
  * no Kids route or tab reaches Quran, prayer, adhan, adhkar, prophets or the mosque; old links redirect to Home;
  * no Kids plan contains `prayerTimes`, `adhan`, `quran`, `adhkar`; tiers are otherwise identical;
  * with `ZADX_VARIANT=kids`: the real build constants are the Kids ones.
* `test/kids_artwork_test.dart` — runs in both builds (the Kids build renders the real scenes):
  1. no Arabic-script character (U+0600–06FF, 0750–077F, 08A0–08FF, FB50–FDFF, FE70–FEFF) in any source under `lib/shared/art`, `lib/shared/widgets`, `lib/features/splash` or the schedule widgets, and none in any text rendered by the Kids scenes, icons and logo;
  2. every Kids painter paints with zero crescents / domes / Islamic stars, `artReligiousMotifs` and every painter default are false with `ZADX_VARIANT=kids`, and drawing one throws there;
  3. a fresh Kids install is English (`AppSettings`, `SettingsController`, picker order);
  4. no Arabic Letters game in the Kids catalogue, routes or deep links.
* `backend/functions/test/security.test.js` — product ids of both apps, same-app line check, packages, and the Kids assistant prompt against the same word list.
* `test/schedule_test.dart` + `LockRulesTest.kt` — the schedule rule on both sides (midnight, weekdays, priority, storage).

## 6. Store and compliance notes

* **Separate listings**: Google Play `com.zadx.kids`, App Store bundle `com.zadx.kids` (App Group `group.com.zadx.kids`). Store text must follow the same rule (no religious words); proposed subtitle: "وقت الشاشة بعد المهام والمذاكرة" / "Screen time after tasks & homework".
* **Children's privacy**: same principles as Zad X Play: COPPA (verifiable parental consent before any personal data, no ads, no third-party trackers), GDPR-K, nickname-only child profiles, no location by default (`FeatureFlags.locationMap` stays off). Needs its **own privacy-policy page** naming Zad X Kids and its own Google Play Data safety form and Families policy declaration (same answers).
* **Accessibility prominent disclosure** (Google Play): the Kids text (in-app and the native service description) mentions study time, reading time and bedtime instead of prayer time. The Play declaration video must be recorded again for `com.zadx.kids`.
* **Products**: create the four `zadx_kids_*` subscriptions in Play Console / App Store Connect with the same prices and the same 7-day on-device trial rule; point the Kids app's Real-time developer notifications to the same `playNotifications` endpoint; give the backend service account access to the Kids app.
* **Firebase**: register `com.zadx.kids` (Android + iOS) in the same Firebase project (same backend, same rules) and ship its own `google-services.json` / `GoogleService-Info.plist`.

## 7. Known gaps / TODO (planned, not in this PR)

1. **Kids logo + launcher icon + store art** (P1 before release): the current logo shows Arabic lettering, a crescent, mosques and "with Islamic Values". Kids draws a Latin text wordmark until a neutral artwork exists. The launcher icon is the `flutter create` default. Store screenshots must be taken in English with the Kids artwork.
2. **iOS Kids build** (P1): `ios/scripts/add_native_files.rb` needs the bundle id / App Group / display name of the variant, and `AppLockPlugin.swift` needs DeviceActivity schedules for the windows (today iOS enforces a schedule only while Zad X runs).
3. **Windows Guard for Kids** (P2): the guard computes prayer locks; it is hidden in Kids until it supports schedules.
4. **Tree-shaking proof** (P2): add a weekly `flutter build apk --release --dart-define=ZADX_VARIANT=kids` job and a symbol check of `libapp.so`. Debug APKs contain the whole Dart kernel, so the Islamic code still exists (unreachable) in the debug Kids APK; the Islamic **assets** are already removed.
5. **Native leftovers**: the Kotlin `PrayerLockReceiver` class and its Arabic block-screen strings are compiled into the Kids APK but never triggered (Kids never schedules prayer alarms, never sends reason `prayer`). A later cleanup can move them behind a resource flag.
6. **Cross-app pairing**: both apps share the Firebase project, so a Zad X Play phone could join a Zad X Kids family. Settings now carry `variant: kids`; the backend could refuse mixed pairing (owner decision 8.6).
7. Small copy polish: the PlayStation/Microsoft notes ("enter these times once…") refer to the prayer play windows, which Kids does not show.
8. **Week starts** (P2, owner decision 8.1): the default study days are Sun–Thu (`schoolDays`); for the US / Europe Mon–Fri is the usual school week.

## 8. Open owner decisions

1. **Default schedules**: bedtime **on** 21:00 → 07:00 every night; study 16:00–18:00 Sun–Thu and reading 19:00–19:30 daily, both **off** until the parent turns them on. OK?
2. **Kids logo / icon / store screenshots**: who designs the neutral artwork, and should it say "Zad X Kids" or just "Zad X"?
3. **Prices and trial** for `zadx_kids_*`: same as Zad X Play ($4.99 / $39.99, $7.99 / $59.99, 7-day Plus trial)?
4. ~~**Arabic Letters game** stays in Kids?~~ **Decided 2026-11-22: removed from Kids** (Western market). Which neutral learning game should Kids get instead (English phonics, numbers, shapes)?
5. **Launch offers**: the Ramadan offer is hidden in Kids. Is there a neutral seasonal offer (e.g. back to school)?
6. **Cross-app families**: allow a Zad X Play device and a Zad X Kids device in one family, or refuse it in `redeemPairingCode`?
7. **Referral codes** work across both apps today (a Play family can refer a Kids family). Keep?
8. **Windows Guard** for Kids: needed for launch or later?
