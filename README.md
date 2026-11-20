# Zad X Play — العب • تعلّم • تألّق

تطبيق عائلي إسلامي: الألعاب بتتفتح بعد الصلاة والمهام، والأذان بيقفل اللعب، ومعاه القرآن والأذكار والتمارين.
An Islamic family app: games unlock after prayer and tasks, the adhan locks play, with Quran, adhkar and exercise.

---

## بالعربي: إيه اللي في المشروع ده؟

| الجزء | الحالة |
|---|---|
| كل الشاشات (الرئيسية، الألعاب، القرآن والأذكار، المهام والتمارين، ولي الأمر، اللغة والبلد، المساعدة، الاشتراك) | ✅ مكتوبة |
| حساب مواقيت الصلاة لـ ٣٣ دولة و٧٦ مدينة + إشعارات الأذان | ✅ مكتوب ومعاه اختبارات |
| منطق المهام والدقايق وقفل الصلاة وموافقة ولي الأمر | ✅ مكتوب ومعاه اختبارات |
| قفل الألعاب على أندرويد (Kotlin) | ✅ مكتوب — يحتاج تجربة على جهاز |
| قفل الألعاب على آيفون (Swift / Screen Time) | ✅ مكتوب — يحتاج موافقة Apple وتجربة على جهاز |
| قفل الألعاب على كمبيوتر ويندوز (برنامج Zad X Guard) | ✅ مكتوب (C#) — يحتاج تجربة على كمبيوتر |
| لوحة ولي الأمر والقرآن والأذكار على الكمبيوتر (ويندوز وماك) والمتصفح | ✅ نفس التطبيق، بيتظبط تلقائيًا للشاشة الكبيرة |
| البلايستيشن والإكس بوكس | ✅ تنبيهات لولي الأمر + فتح التطبيق الرسمي (PlayStation Family و Microsoft Family Safety) |
| ربط جهاز الأب بجهاز الطفل والكمبيوتر بكود | ✅ مكتوب |
| الاشتراكات ونظام الدعوات والمساعد الذكي (Firebase) | ✅ مكتوب — يحتاج إعداد حسابات |
| ألعاب Zad X التعليمية الداخلية | ⏳ الأزرار موجودة، الألعاب نفسها لسه |
| قفل الألعاب على الماك | ⏳ محتاج دراسة (مرحلة جاية) |
| أكتر من طفل في نفس العيلة | ⏳ الكود جاهز لطفل واحد، والتوسعة موصوفة في docs/ARCHITECTURE.md |

**مهم:** الكود اتكتب من غير ما يتشغّل على Flutter أو موبايل، فأول خطوة للمبرمج إنه يشغّله ويصلّح أي أخطاء صغيرة تظهر.

**قبل النشر لازم:**
1. شيخ أو متخصص يراجع نصوص الأذكار (`lib/data/catalog/adhkar.dart`).
2. ملفات صوت أذان مرخّصة (`assets/audio/`).
3. موافقة Apple على صلاحية Family Controls (ممكن تاخد أسابيع، ابدأ بدري).
4. نموذج Google Play الخاص بصلاحية Accessibility.

التفاصيل في `docs/STORE_CHECKLIST.md`.

---

## Developer setup

Requirements: Flutter ≥ 3.27, Xcode 16 (iOS 16+), Android Studio, Node 20 (backend).

```bash
# 1. Generate the native shells around this code (keeps lib/, android/, ios/ files)
flutter create --org com.zadx --project-name zadx --platforms android,ios,web,windows,macos .

# 2. Re-apply our native files if flutter create overwrote any
git checkout -- android/app/src/main/kotlin ios/Runner/AppDelegate.swift   # if using git

# 3. Dependencies + localizations
flutter pub get
flutter gen-l10n

# 4. Firebase (optional for local dev — app runs single-device without it)
dart pub global activate flutterfire_cli
flutterfire configure

# 5. Run
flutter test
flutter run
```

### Android
- Merge `android/app/src/main/AndroidManifest.additions.xml` into `AndroidManifest.xml`.
- `minSdkVersion 26`, `compileSdk 35` in `android/app/build.gradle`.
- Add `res/raw/adhan_short.mp3` (licensed).
- Before sending the user to Accessibility settings, show a prominent disclosure screen (Play policy).

### iOS
See `ios/README_IOS.md` (Family Controls entitlement, two extensions, App Group).

### Web / Windows / macOS (parent dashboard, Quran, adhkar)
```bash
flutter run -d chrome      # web
flutter run -d windows
flutter run -d macos       # add com.apple.security.network.client to macos/Runner/*.entitlements
```
On these platforms the app never tries to lock games (see `lib/core/platform.dart`);
purchases are made on the phone.

### Windows game lock
See `windows_guard/README.md` (C# service, installed with a pairing code).

### Backend
See `backend/README.md`.

## Project structure
```
lib/
  core/            config (brand, prices, product ids), theme, formatting
  data/catalog/    countries & cities, games, surah index, adhkar, default tasks
  data/models/     task, game, location, plan, surah
  features/        one folder per screen + controllers (Riverpod)
  services/        app lock bridge, audio, notifications, billing, referral, AI, Quran text, family sync
android/…/kotlin   AppBlockerService (Accessibility), BlockActivity, LockStore, PrayerLockReceiver
ios/               AppLockPlugin, DeviceActivity monitor + shield extensions
backend/           Firestore rules + Cloud Functions (AI proxy, purchases, referrals, notifications,
                   device pairing, Windows guard policy API)
windows_guard/     Zad X Guard — Windows service that locks PC games with the same rules
test/              prayer times, wallet rules, referral rewards, catalog integrity
```

Architecture notes: `docs/ARCHITECTURE.md`.
