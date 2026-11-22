import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/catalog/reading_stories.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/reading/reading_screen.dart';
import 'package:zadx/features/reading/reading_tasks.dart';
import 'package:zadx/features/reading/reading_timer_store.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/services/family/children_controller.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';

Future<ProviderContainer> makeContainer() async {
  SharedPreferences.setMockInitialValues({'settings.language': 'en'});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 20, 10), 2)),
    nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> pumpReading(WidgetTester tester, ProviderContainer container, String taskId, {String lang = 'en'}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ReadingTaskScreen(taskId: taskId),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Taps without letting time pass (keeps the reading timer exact).
Future<void> tapNow(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  // The screens are lazy ListViews: scroll until the widget is built and on screen.
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('stories catalogue', () {
    test('at least 6 stories, every level covered, 2–3 valid questions each', () {
      expect(readingStories.length, greaterThanOrEqualTo(6));
      for (final level in ReadingLevel.values) {
        expect(storiesFor(level).length, greaterThanOrEqualTo(2), reason: level.name);
      }
      expect(readingStories.map((s) => s.id).toSet().length, readingStories.length, reason: 'unique ids');
      for (final s in readingStories) {
        expect(s.questions.length, inInclusiveRange(2, 3), reason: s.id);
        expect(s.paragraphs, isNotEmpty);
        for (final p in [s.title, ...s.paragraphs]) {
          expect(p.ar.trim(), isNotEmpty, reason: s.id);
          expect(p.en.trim(), isNotEmpty, reason: s.id);
        }
        for (final q in s.questions) {
          expect(q.options.length, inInclusiveRange(2, 4), reason: s.id);
          expect(q.answer, inInclusiveRange(0, q.options.length - 1), reason: s.id);
        }
      }
    });

    test('stories stay general: no scripture, hadith or rulings (no scholar review needed)', () {
      // Whole words only ("المكسورة" must not match "سورة").
      const bannedAr = {'الله', 'قرآن', 'حديث', 'سورة', 'آية', 'حلال', 'حرام', 'نبي', 'صلاة', 'دعاء'};
      final bannedEn = RegExp(r'\b(allah|god|quran|hadith|surah|verse|halal|haram|prophet|prayer|pray)\b', caseSensitive: false);
      final arWord = RegExp(r'[\u0621-\u064A\u0671-\u06D3]+');
      String bare(String w) => w.startsWith('ال') && w.length > 3 ? w.substring(2) : w;
      for (final s in readingStories) {
        final all = [s.title, ...s.paragraphs, for (final q in s.questions) ...[q.prompt, ...q.options]];
        for (final t in all) {
          for (final m in arWord.allMatches(t.ar)) {
            final w = m[0]!;
            expect(bannedAr.contains(w) || bannedAr.contains(bare(w)), isFalse, reason: '${s.id}: "$w"');
          }
          expect(bannedEn.hasMatch(t.en), isFalse, reason: '${s.id}: ${t.en}');
        }
      }
    });
  });

  test('reading task survives a JSON round trip, and unknown values are ignored', () {
    final story = ReadingTasks.story(ReadingLevel.age8to10);
    final back = TaskDefinition.fromJson(story.toJson());
    expect(back.kind, TaskKind.reading);
    expect(back.readingMode, ReadingMode.story);
    expect(back.readingLevel, ReadingLevel.age8to10);

    final book = TaskDefinition.fromJson(ReadingTasks.book(20).toJson());
    expect(book.readingMode, ReadingMode.paperBook);
    expect(book.readingMinutes, 20);

    final odd = TaskDefinition.fromJson({...story.toJson(), 'readingMode': 'audio', 'readingLevel': 'age99'});
    expect(odd.readingMode, isNull);
    expect(odd.readingLevel, isNull);

    // Older tasks without the new fields still load.
    final legacy = TaskDefinition.fromJson({
      'id': 'room',
      'titleAr': 'a',
      'titleEn': 'b',
      'subAr': 'c',
      'subEn': 'd',
      'kind': 'chore',
      'rewardMinutes': 10,
      'color': 0xFF000000,
    });
    expect(legacy.readingMode, isNull);
    expect(legacy.toJson().containsKey('readingMode'), isFalse);
  });

  test('a handed-in reading task earns nothing until the parent approves it', () async {
    final c = await makeContainer();
    final wallet = c.read(walletProvider.notifier);
    wallet.upsertTask(ReadingTasks.book(10));
    final before = c.read(walletProvider).earnedMinutes;

    wallet.submit(ReadingTasks.bookId);
    expect(c.read(walletProvider).progressOf(ReadingTasks.bookId).status, TaskStatus.pending);
    expect(c.read(walletProvider).pending.map((t) => t.id), contains(ReadingTasks.bookId));
    expect(c.read(walletProvider).earnedMinutes, before);

    wallet.approve(ReadingTasks.bookId);
    expect(c.read(walletProvider).progressOf(ReadingTasks.bookId).status, TaskStatus.done);
    expect(c.read(walletProvider).earnedMinutes, before + ReadingTasks.rewardMinutes);
  });

  testWidgets('story: read, answer (wrong then right), hand in → pending → parent confirms', (tester) async {
    final c = await makeContainer();
    c.read(walletProvider.notifier).upsertTask(ReadingTasks.story(ReadingLevel.age5to7));
    await pumpReading(tester, c, ReadingTasks.storyId);

    // Only stories of the parent's level are offered.
    expect(find.byKey(const Key('story_little_seed')), findsOneWidget);
    expect(find.byKey(const Key('story_bee_garden')), findsNothing);

    await tapKey(tester, 'story_little_seed');
    expect(find.text('The Little Seed'), findsOneWidget);
    await tapKey(tester, 'readingDoneButton');

    // Q1: a wrong answer does not move on.
    await tapKey(tester, 'option_1');
    expect(find.byKey(const Key('readingNextButton')), findsNothing);
    await tapKey(tester, 'option_0');
    await tapKey(tester, 'readingNextButton');

    // Q2 (last): answering it hands the task in.
    final seed = storyById('little_seed')!;
    await tapKey(tester, 'option_${seed.questions[1].answer}');
    expect(c.read(walletProvider).progressOf(ReadingTasks.storyId).status, TaskStatus.todo);
    final earned = c.read(walletProvider).earnedMinutes;
    await tapKey(tester, 'readingNextButton');

    expect(find.byKey(const Key('readingFinished')), findsOneWidget);
    expect(c.read(walletProvider).progressOf(ReadingTasks.storyId).status, TaskStatus.pending);
    expect(c.read(walletProvider).earnedMinutes, earned, reason: 'the child cannot self-approve');

    // Parent approves (Parent → Approvals, behind the PIN): the normal reward is earned.
    c.read(walletProvider.notifier).approve(ReadingTasks.storyId);
    expect(c.read(walletProvider).earnedMinutes, earned + ReadingTasks.rewardMinutes);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('paper book: cannot hand in before the timer ends, then goes to the parent', (tester) async {
    final c = await makeContainer();
    c.read(walletProvider.notifier).upsertTask(ReadingTasks.book(10));
    await pumpReading(tester, c, ReadingTasks.bookId);

    expect(find.byKey(const Key('readingSendButton')), findsNothing);
    expect(find.text('10:00'), findsOneWidget);

    await tapNow(tester, 'readingTimerButton'); // start
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(find.text('05:00'), findsOneWidget);
    expect(find.byKey(const Key('readingSendButton')), findsNothing);

    // A break pauses the timer.
    await tapNow(tester, 'readingTimerButton');
    await tester.pump(const Duration(minutes: 3));
    expect(find.text('05:00'), findsOneWidget);

    await tapNow(tester, 'readingTimerButton'); // keep reading
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();
    expect(find.text('00:00'), findsOneWidget);
    expect(c.read(walletProvider).progressOf(ReadingTasks.bookId).status, TaskStatus.todo);

    await tapKey(tester, 'readingSendButton');
    expect(find.byKey(const Key('readingFinished')), findsOneWidget);
    expect(c.read(walletProvider).progressOf(ReadingTasks.bookId).status, TaskStatus.pending);

    await tester.pumpWidget(const SizedBox());
  });

  group('paper-book timer is kept per child and task', () {
    test('store: per child + task, a new day starts at zero, a running timer comes back paused', () async {
      SharedPreferences.setMockInitialValues({});
      final store = ReadingTimerStore(await SharedPreferences.getInstance());
      const day = '2026-11-20';
      expect(store.load('child-1', 'reading_book', day), const ReadingTimerProgress(day: day));

      await store.save('child-1', 'reading_book', const ReadingTimerProgress(day: day, seconds: 125, running: true, startedAtMs: 7));
      final back = store.load('child-1', 'reading_book', day);
      expect(back.seconds, 125);
      expect(back.running, isFalse, reason: 'time while Zad X was closed is never counted');
      expect(back.startedAtMs, 7);

      expect(store.load('child-2', 'reading_book', day).seconds, 0, reason: 'another child has its own timer');
      expect(store.load('child-1', 'other_task', day).seconds, 0);
      expect(store.load('child-1', 'reading_book', '2026-11-21').seconds, 0, reason: 'a new day starts again');

      await store.clear('child-1', 'reading_book');
      expect(store.load('child-1', 'reading_book', day).seconds, 0);
      expect(ReadingTimerProgress.fromJson({'day': day, 'seconds': -4}), isNull);
      expect(ReadingTimerProgress.fromJson('junk'), isNull);
    });

    testWidgets('leaving the screen keeps the time read (paused), coming back continues', (tester) async {
      final c = await makeContainer();
      c.read(walletProvider.notifier).upsertTask(ReadingTasks.book(10));
      await pumpReading(tester, c, ReadingTasks.bookId);

      await tapNow(tester, 'readingTimerButton'); // start
      await tester.pump(const Duration(minutes: 2));
      await tester.pump();
      expect(find.text('08:00'), findsOneWidget);

      // The child leaves the screen (or Zad X is closed), then comes back.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 5));
      await pumpReading(tester, c, ReadingTasks.bookId);
      expect(find.text('08:00'), findsOneWidget, reason: 'not reset, and the time away is not counted');
      expect(find.text('Keep reading'), findsOneWidget);

      await tapNow(tester, 'readingTimerButton');
      await tester.pump(const Duration(minutes: 8));
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);
      await tapKey(tester, 'readingSendButton');
      expect(c.read(walletProvider).progressOf(ReadingTasks.bookId).status, TaskStatus.pending);
      final prefs = c.read(sharedPrefsProvider);
      expect(prefs.getKeys().where((k) => k.startsWith('reading.timer.')), isEmpty, reason: 'cleared after hand-in');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Zad X in the background pauses the timer', (tester) async {
      final c = await makeContainer();
      c.read(walletProvider.notifier).upsertTask(ReadingTasks.book(10));
      await pumpReading(tester, c, ReadingTasks.bookId);

      await tapNow(tester, 'readingTimerButton');
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();
      expect(find.text('09:00'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(minutes: 4));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('09:00'), findsOneWidget);
      expect(find.text('Keep reading'), findsOneWidget);
      // Saved for the active child as paused, with the minute read.
      final saved = c.read(readingTimerStoreProvider).load(c.read(activeChildIdProvider), ReadingTasks.bookId, c.read(walletProvider).day);
      expect(saved.seconds, 60);
      expect(saved.running, isFalse);

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('Arabic: right-to-left with Arabic digits; already handed-in task shows its status', (tester) async {
    final c = await makeContainer();
    c.read(walletProvider.notifier)
      ..upsertTask(ReadingTasks.book(15))
      ..submit(ReadingTasks.bookId);
    await pumpReading(tester, c, ReadingTasks.bookId, lang: 'ar');

    expect(Directionality.of(tester.element(find.byType(ReadingTaskScreen))), TextDirection.rtl);
    expect(find.byKey(const Key('readingTimerButton')), findsNothing);
    expect(find.byKey(const Key('readingSendButton')), findsNothing);

    c.read(walletProvider.notifier).reject(ReadingTasks.bookId);
    await tester.pumpAndSettle();
    expect(find.text('١٥:٠٠'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('story buttons are large enough for small fingers (≥48dp)', (tester) async {
    final c = await makeContainer();
    c.read(walletProvider.notifier).upsertTask(ReadingTasks.story(ReadingLevel.age8to10));
    await pumpReading(tester, c, ReadingTasks.storyId);
    expect(tester.getSize(find.byKey(const Key('story_broken_vase'))).height, greaterThanOrEqualTo(48));
    await tapKey(tester, 'story_broken_vase');
    await tapKey(tester, 'readingDoneButton');
    for (var i = 0; i < 3; i++) {
      expect(tester.getSize(find.byKey(Key('option_$i'))).height, greaterThanOrEqualTo(48));
    }
    await tester.pumpWidget(const SizedBox());
  });
}
