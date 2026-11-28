// Owner decision 2026-11-28 (zero cost, no Cloud Functions, no push): child devices write event
// docs + presence; the parent app shows them in the parent area and as local notifications while
// it is open. These tests cover the rules, the parent card and the notifier.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/core/feature_flags.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/features/parent/family_alerts.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/family_events.dart';
import 'package:zadx/services/family/family_repository.dart';
import 'package:zadx/services/family/presence_reporter.dart';

class _EventsRepo extends LocalFamilyRepository {
  final events = StreamController<List<FamilyEvent>>.broadcast();
  final presence = StreamController<Map<String, ChildPresence>>.broadcast();
  var pruned = 0;

  @override
  Stream<List<FamilyEvent>> watchEvents() => events.stream;

  @override
  Stream<Map<String, ChildPresence>> watchPresence() => presence.stream;

  @override
  Future<void> pruneEvents() async => pruned++;
}

class _PresenceRepo extends LocalFamilyRepository {
  final touched = <String>[];

  @override
  Future<void> touchPresence(String childId, {required String platform}) async => touched.add(childId);
}

class _FakeSink implements FamilyAlertSink {
  final shown = <String>[];

  @override
  Future<void> show(int id, String title, String body) async => shown.add(body);
}

FamilyEvent _event(String id, String type, DateTime at, {String child = ChildProfile.defaultId}) =>
    FamilyEvent(id: id, type: type, childId: child, at: at);

void main() {
  final now = DateTime.now().toUtc();

  group('event docs', () {
    test('fields: type, childId and a short detail only; unknown reasons dropped', () {
      expect(eventFields('task_submitted', 'child-1', detail: 'task-7'), {
        'type': 'task_submitted',
        'childId': 'child-1',
        'detail': 'task-7',
      });
      expect(eventFields('adhan', 'child-1', detail: 'x' * 200)['detail'], hasLength(maxEventDetailLength));
      expect(eventFields('protection', 'c', reasons: const ['accessibility_off']), containsPair('reasons', ['accessibility_off']));
      expect(eventDetailFrom(const {'taskId': 't1'}), 't1');
      expect(eventDetailFrom(const {'prayer': 'fajr'}), 'fajr');
      expect(eventDetailFrom(const {'name': 'Ali'}), isNull); // nothing else is copied
    });

    test('parsing fails closed: unknown type or missing child is never shown', () {
      expect(FamilyEvent.tryParse('a', {'type': 'hack', 'childId': 'c'}), isNull);
      expect(FamilyEvent.tryParse('a', {'type': 'adhan'}), isNull);
      final e = FamilyEvent.tryParse('a', {
        'type': 'protection',
        'childId': 'c',
        'at': now,
        'reasons': ['accessibility_off', 'evil', 3],
      })!;
      expect(e.reasons, ['accessibility_off']);
      expect(e.at, now);
    });

    test('protection: only new reasons are alerted', () {
      expect(newTamperReasons(const [], const ['accessibility_off']), ['accessibility_off']);
      expect(newTamperReasons(const ['accessibility_off'], const ['accessibility_off', 'clock_changed']), ['clock_changed']);
      expect(newTamperReasons(const ['accessibility_off'], const []), isEmpty);
      expect(cleanTamperReasons(const ['clock_changed', 'x', 'accessibility_off', 'clock_changed']), ['accessibility_off', 'clock_changed']);
    });

    test('presence: one write per 15 minutes at most', () {
      expect(shouldTouchPresence(null, now), isTrue);
      expect(shouldTouchPresence(now.subtract(const Duration(minutes: 14)), now), isFalse);
      expect(shouldTouchPresence(now.subtract(const Duration(minutes: 15)), now), isTrue);
      expect(shouldTouchPresence(now.add(const Duration(hours: 1)), now), isTrue); // clock went back
    });

    test('a device silent for over a day is stale', () {
      expect(ChildPresence(childId: 'c', lastSeen: now.subtract(const Duration(hours: 23))).isStale(now), isFalse);
      expect(ChildPresence(childId: 'c', lastSeen: now.subtract(const Duration(hours: 25))).isStale(now), isTrue);
      expect(const ChildPresence(childId: 'c').isStale(now), isFalse);
    });

    test('notify: only events after the last notified one, oldest first; unstamped events wait', () {
      final a = _event('a', 'task_submitted', now.subtract(const Duration(minutes: 5)));
      final b = _event('b', 'adhan', now.subtract(const Duration(minutes: 1)));
      const pending = FamilyEvent(id: 'p', type: 'task_submitted', childId: 'c');
      final old = _event('o', 'task_submitted', now.subtract(const Duration(hours: 2)));
      final out = eventsToNotify([b, pending, old, a], now.subtract(const Duration(hours: 1)));
      expect(out.map((e) => e.id), ['a', 'b']);
    });

    test('notify: an event with microseconds is not notified again after its ms mark', () {
      final at = DateTime.utc(2026, 11, 28, 12, 0, 0, 123, 456);
      final e = FamilyEvent(id: 'u', type: 'task_submitted', childId: 'c', at: at);
      final mark = DateTime.fromMillisecondsSinceEpoch(at.millisecondsSinceEpoch, isUtc: true);
      expect(eventsToNotify([e], mark), isEmpty);
    });

    test('notification settings filter task and adhan alerts; protection always passes', () {
      final task = _event('t', 'task_submitted', now);
      final adhan = _event('a', 'adhan', now);
      final prot = _event('p', 'protection', now);
      bool wanted(FamilyEvent e, {bool tasks = true, bool adhanOn = true, bool supported = true}) =>
          eventWanted(e, notifyOnTasks: tasks, notifyOnAdhan: adhanOn, adhanSupported: supported);
      expect(wanted(task, tasks: false), isFalse);
      expect(wanted(adhan, adhanOn: false), isFalse);
      expect(wanted(adhan, supported: false), isFalse); // Zad X Kids
      expect(wanted(prot, tasks: false, adhanOn: false), isTrue);
    });
  });

  group('parent phone', () {
    late SharedPreferences prefs;

    Future<(_EventsRepo, _FakeSink, ProviderContainer)> setUpParent(WidgetTester tester, {String lang = 'en', bool childDevice = false, Map<String, Object> extra = const {}}) async {
      SharedPreferences.setMockInitialValues({
        if (childDevice) ChildStorage.boundKey: ChildProfile.defaultId,
        'settings.language': lang,
        ...extra,
      });
      prefs = await SharedPreferences.getInstance();
      final repo = _EventsRepo();
      final sink = _FakeSink();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          familyRepositoryProvider.overrideWithValue(repo),
          familyAlertSinkProvider.overrideWithValue(sink),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            ref.watch(familyAlertsNotifierProvider);
            return MaterialApp(
              locale: Locale(lang),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(body: SingleChildScrollView(child: FamilyAlertsCard())),
            );
          },
        ),
      ));
      await tester.pump();
      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      return (repo, sink, container);
    }

    testWidgets('local (one-device) family: no card', (tester) async {
      await setUpParent(tester);
      expect(find.byKey(const Key('familyAlertsCard')), findsNothing);
    });

    testWidgets('events and last seen are shown to the parent, newest first', (tester) async {
      final (repo, _, _) = await setUpParent(tester);
      repo.presence.add({
        ChildProfile.defaultId: ChildPresence(childId: ChildProfile.defaultId, lastSeen: now.subtract(const Duration(minutes: 3))),
      });
      repo.events.add([
        _event('e1', 'task_submitted', now.subtract(const Duration(hours: 2))),
        _event('e2', 'protection', now.subtract(const Duration(minutes: 10))),
        _event('old', 'task_submitted', now.subtract(const Duration(days: 9))),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('familyAlertsCard')), findsOneWidget);
      expect(find.text('Family alerts'), findsOneWidget);
      expect(find.textContaining('Last seen: '), findsOneWidget);
      expect(find.text('A task is waiting for your approval'), findsOneWidget);
      expect(find.textContaining('Zad X protection was turned off'), findsOneWidget);
      expect(find.byKey(const ValueKey('familyEvent-old')), findsNothing); // older than 7 days
      final y1 = tester.getTopLeft(find.byKey(const ValueKey('familyEvent-e2'))).dy;
      final y2 = tester.getTopLeft(find.byKey(const ValueKey('familyEvent-e1'))).dy;
      expect(y1, lessThan(y2));
    });

    testWidgets('a silent child device is flagged in the card', (tester) async {
      final (repo, _, _) = await setUpParent(tester);
      repo.presence.add({
        ChildProfile.defaultId: ChildPresence(childId: ChildProfile.defaultId, lastSeen: now.subtract(const Duration(days: 2))),
      });
      repo.events.add(const []);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('stale-${ChildProfile.defaultId}')), findsOneWidget);
      expect(find.text('No alerts in the last 7 days.'), findsOneWidget);
    });

    testWidgets('Arabic card', (tester) async {
      final (repo, _, _) = await setUpParent(tester, lang: 'ar');
      repo.events.add([_event('e1', 'task_submitted', now.subtract(const Duration(minutes: 1)))]);
      await tester.pump();
      await tester.pump();
      expect(find.text('تنبيهات العائلة'), findsOneWidget);
      expect(find.text('فيه مهمة مستنية موافقتك'), findsOneWidget);
    });

    testWidgets('first run never floods old alerts; later events become local notifications', (tester) async {
      final (repo, sink, _) = await setUpParent(tester);
      repo.events.add([_event('old', 'task_submitted', now.subtract(const Duration(minutes: 30)))]);
      await tester.pump();
      expect(sink.shown, isEmpty);
      expect(prefs.getInt(alertsNotifiedUntilKey), isNotNull);

      final later = DateTime.now().toUtc().add(const Duration(seconds: 5));
      repo.events.add([
        _event('new', 'task_submitted', later),
        _event('old', 'task_submitted', now.subtract(const Duration(minutes: 30))),
      ]);
      await tester.pump();
      expect(sink.shown, ['A task is waiting for your approval']);

      // The same event again (e.g. resume): not notified twice.
      repo.events.add([_event('new', 'task_submitted', later)]);
      await tester.pump();
      expect(sink.shown, hasLength(1));
      expect(repo.pruned, 1);
    });

    testWidgets('notification text never contains the child name', (tester) async {
      final (repo, sink, _) = await setUpParent(
        tester,
        extra: {alertsNotifiedUntilKey: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch},
      );
      repo.events.add([_event('p', 'protection', now)]);
      await tester.pump();
      expect(sink.shown.single, contains('protection'));
      expect(sink.shown.single, isNot(contains('child-1')));
    });

    testWidgets('a stale device is notified once per last-seen time', (tester) async {
      final (repo, sink, _) = await setUpParent(tester);
      final seen = now.subtract(const Duration(days: 2));
      repo.presence.add({ChildProfile.defaultId: ChildPresence(childId: ChildProfile.defaultId, lastSeen: seen)});
      await tester.pump();
      repo.presence.add({ChildProfile.defaultId: ChildPresence(childId: ChildProfile.defaultId, lastSeen: seen)});
      await tester.pump();
      expect(sink.shown, hasLength(1));
      expect(sink.shown.single, contains('has not checked in'));
    });

    testWidgets('a paired child device reads no alerts', (tester) async {
      final (repo, sink, container) = await setUpParent(tester, childDevice: true);
      expect(repo.events.hasListener, isFalse);
      expect(container.read(isParentAlertDeviceProvider), isFalse);
      expect(sink.shown, isEmpty);
    });

    // A plain async test (not testWidgets): the child providers start streams whose zero-delay
    // Riverpod refresh timers would trip the fake-async "timers pending" check.
    test('child device: "last seen" is written at start, then at most every 15 minutes', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({ChildStorage.boundKey: ChildProfile.defaultId});
      prefs = await SharedPreferences.getInstance();
      final repo = _PresenceRepo();
      ProviderContainer start() {
        final c = ProviderContainer(overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          familyRepositoryProvider.overrideWithValue(repo),
        ]);
        c.listen(presenceReporterProvider, (_, __) {});
        return c;
      }

      final first = start();
      await pumpEventQueue();
      expect(repo.touched, [ChildProfile.defaultId]);
      first.dispose();
      final second = start(); // app restarted right away
      await pumpEventQueue();
      expect(repo.touched, hasLength(1));
      expect(prefs.getInt(presenceLastWriteKey), isNotNull);
      second.dispose(); // stops the 15-minute timer before the test ends
      await pumpEventQueue();
    });

    testWidgets('parent phone: never writes presence', (tester) async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      final repo = _PresenceRepo();
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        familyRepositoryProvider.overrideWithValue(repo),
      ]);
      c.listen(presenceReporterProvider, (_, __) {});
      await tester.pump();
      expect(repo.touched, isEmpty);
      c.dispose();
    });

    testWidgets('Blaze build: the server pushes, so no local notifications', (tester) async {
      SharedPreferences.setMockInitialValues({alertsNotifiedUntilKey: 0});
      prefs = await SharedPreferences.getInstance();
      final repo = _EventsRepo();
      final sink = _FakeSink();
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        familyRepositoryProvider.overrideWithValue(repo),
        familyAlertSinkProvider.overrideWithValue(sink),
        featureFlagsProvider.overrideWithValue(const FeatureFlags(serverFunctionsRequested: true)),
      ]);
      addTearDown(c.dispose);
      c.listen(familyAlertsNotifierProvider, (_, __) {});
      repo.events.add([_event('x', 'task_submitted', now)]);
      await tester.pump();
      expect(sink.shown, isEmpty);
    });
  });
}
