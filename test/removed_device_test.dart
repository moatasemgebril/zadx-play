import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/family/removed_device_screen.dart';
import 'package:zadx/features/parent/parent_session.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';
import 'package:zadx/services/app_lock/app_lock_service.dart';
import 'package:zadx/services/billing/subscription_service.dart';
import 'package:zadx/services/family/approval_queue.dart';
import 'package:zadx/services/family/child_pause.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/children_controller.dart';
import 'package:zadx/services/family/device_removal.dart';
import 'package:zadx/services/family/family_bootstrap.dart';
import 'package:zadx/services/family/family_repository.dart';

/// BACKLOG P1-3a: a device the parent removed from the family (removeLinkedDevice) shows a calm
/// "removed" screen, forgets the old family and stays LOCKED until a parent sets it up again.

/// Server answers in order; the last one repeats.
class _FakeSource implements MembershipSource {
  _FakeSource(this.answers);
  final List<MembershipProbe> answers;
  final denied = StreamController<void>.broadcast();
  int calls = 0;

  @override
  Stream<void> accessDenied() => denied.stream;

  @override
  Future<MembershipProbe> probe() async {
    final a = answers[calls < answers.length ? calls : answers.length - 1];
    calls++;
    return a;
  }
}

const _free = Entitlement();
const _oldFamilyId = 'oldFamily1';

/// Old family data on a paired child device: names, wallet, plan cache, queue, family id.
Map<String, Object> _pairedChildPrefs() => {
      'settings.language': 'en',
      FamilyBootstrap.idKey: _oldFamilyId,
      ChildStorage.boundKey: 'cyusuf',
      ChildStorage.activeKey: 'cyusuf',
      ChildStorage.childrenKey: '[{"id":"cyusuf","nickname":"Yusuf","avatar":"star"}]',
      ChildStorage.walletKey('cyusuf'): '{"day":"2026-11-21","progress":{},"usedMinutes":5,"prayerLock":false}',
      ChildStorage.tasksKey('cyusuf'): '[]',
      ChildStorage.eduStarsKey('cyusuf'): 12,
      ChildStorage.familyStatusKey: '{"createdAt":1}',
      ApprovalQueue.storageKey: '[]',
      'billing.verified.tier': 'plus',
      'billing.verified.atMs': 1,
    };

class _Session {
  int signOuts = 0;
  int freshFamilies = 0;
  String? freshId;

  RemovalSession get value => RemovalSession(
        signOut: () async => signOuts++,
        startFreshFamily: (_) async {
          freshFamilies++;
          return freshId;
        },
      );
}

Future<(ProviderContainer, SharedPreferences, _Session)> _container(
  _FakeSource source, {
  Map<String, Object>? prefs,
  FamilyPlanStatus? status,
}) async {
  SharedPreferences.setMockInitialValues(prefs ?? _pairedChildPrefs());
  final p = await SharedPreferences.getInstance();
  final session = _Session();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(p),
    familyIdProvider.overrideWith((_) => p.getString(FamilyBootstrap.idKey)),
    membershipSourceProvider.overrideWith((ref) => ref.watch(familyIdProvider) == null ? null : source),
    removalConfirmDelayProvider.overrideWithValue(Duration.zero),
    removalSessionProvider.overrideWithValue(session.value),
    cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 21, 10), 2)),
    nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
    clockProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 11, 21, 8))),
    planEntitlementProvider.overrideWithValue(_free),
    familyPlanStatusProvider.overrideWith((ref) => Stream.value(status)),
  ]);
  addTearDown(c.dispose);
  addTearDown(source.denied.close);
  await c.read(familyPlanStatusProvider.future);
  await c.read(clockProvider.future);
  return (c, p, session);
}

/// Lets the async watcher and the fake server answers run.
Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Every stored value as text, to check that no old family name is left anywhere.
String _allPrefsText(SharedPreferences p) => [for (final k in p.getKeys()) '$k=${p.get(k)}'].join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('server answer', () {
    test('only an explicit boolean counts', () {
      expect(membershipFromServer({'member': true}), MembershipProbe.member);
      expect(membershipFromServer({'member': false}), MembershipProbe.notMember);
      expect(membershipFromServer(null), MembershipProbe.unknown);
      expect(membershipFromServer({'member': 'false'}), MembershipProbe.unknown);
      expect(membershipFromServer({}), MembershipProbe.unknown);
      expect(membershipFromServer('removed'), MembershipProbe.unknown);
    });
  });

  group('RemovalDetector: removed vs offline', () {
    const detector = RemovalDetector(delay: Duration.zero);

    test('two explicit "not a member" answers in a row = removed', () async {
      final s = _FakeSource([MembershipProbe.notMember]);
      expect(await detector.isRemoved(s.probe), isTrue);
      expect(s.calls, 2);
    });

    test('offline / timeout / function error (unknown) is never a removal', () async {
      final s = _FakeSource([MembershipProbe.unknown]);
      expect(await detector.isRemoved(s.probe), isFalse);
      expect(s.calls, 1);
    });

    test('one "not a member" followed by offline is not enough', () async {
      final s = _FakeSource([MembershipProbe.notMember, MembershipProbe.unknown]);
      expect(await detector.isRemoved(s.probe), isFalse);
    });

    test('a member (e.g. permission-denied from a rules mistake) is not removed', () async {
      final s = _FakeSource([MembershipProbe.member]);
      expect(await detector.isRemoved(s.probe), isFalse);
    });
  });

  group('DeviceRemovalController', () {
    test('offline: nothing changes, the old family and its data stay', () async {
      final (c, p, session) = await _container(_FakeSource([MembershipProbe.unknown]));
      expect(await c.read(deviceRemovalProvider.notifier).check(), isFalse);
      expect(c.read(deviceRemovalProvider), isFalse);
      expect(p.getString(FamilyBootstrap.idKey), _oldFamilyId);
      expect(c.read(familyIdProvider), _oldFamilyId);
      expect(c.read(childrenProvider).boundChildId, 'cyusuf');
      expect(session.signOuts, 0);
    });

    test('removed: resets to a fresh local family and leaks nothing of the old one', () async {
      final (c, p, session) = await _container(_FakeSource([MembershipProbe.notMember]));
      expect(await c.read(deviceRemovalProvider.notifier).check(), isTrue);

      expect(c.read(deviceRemovalProvider), isTrue);
      expect(p.getBool(DeviceRemoval.removedKey), isTrue);
      expect(p.getBool(DeviceRemoval.clearCacheKey), isTrue); // Firestore cache cleared next start
      expect(c.read(familyIdProvider), isNull);
      expect(c.read(familyRepositoryProvider), isA<LocalFamilyRepository>());
      for (final key in [
        FamilyBootstrap.idKey,
        ChildStorage.boundKey,
        ChildStorage.familyStatusKey,
        ApprovalQueue.storageKey,
        ChildStorage.walletKey('cyusuf'),
        ChildStorage.eduStarsKey('cyusuf'),
        'billing.verified.tier',
      ]) {
        expect(p.containsKey(key), isFalse, reason: key);
      }
      expect(_allPrefsText(p), isNot(contains('Yusuf')));
      expect(_allPrefsText(p), isNot(contains(_oldFamilyId)));
      final children = c.read(childrenProvider);
      expect(children.isBound, isFalse);
      expect(children.children.map((k) => k.nickname).toList(), ['']); // a fresh child without a name
      expect(session.signOuts, 1);
    });

    test('paired to another family during the check: the answer is ignored', () async {
      final source = _FakeSource([MembershipProbe.notMember]);
      final (c, p, _) = await _container(source);
      final pending = c.read(deviceRemovalProvider.notifier).check();
      c.read(familyIdProvider.notifier).state = 'newFamily2';
      expect(await pending, isFalse);
      expect(c.read(deviceRemovalProvider), isFalse);
      expect(p.getString(ChildStorage.boundKey), 'cyusuf');
    });

    test('the permission-denied hint triggers the server check', () async {
      final source = _FakeSource([MembershipProbe.notMember]);
      final (c, _, _) = await _container(source);
      c.read(deviceRemovalWatcherProvider);
      source.denied.add(null);
      await _settle();
      expect(source.calls, 2);
      expect(c.read(deviceRemovalProvider), isTrue);
    });

    test('a hint while offline does not remove the device', () async {
      final source = _FakeSource([MembershipProbe.unknown]);
      final (c, _, _) = await _container(source);
      c.read(deviceRemovalWatcherProvider);
      source.denied.add(null);
      await _settle();
      expect(source.calls, 1);
      expect(c.read(deviceRemovalProvider), isFalse);
    });

    test('the removed state survives a restart', () async {
      final (c, _, _) = await _container(
        _FakeSource([MembershipProbe.unknown]),
        prefs: {'settings.language': 'en', DeviceRemoval.removedKey: true},
      );
      expect(c.read(deviceRemovalProvider), isTrue);
      expect(c.read(lockPolicyProvider).locked, isTrue);
    });

    test('parent set-up leaves the removed state with a fresh family', () async {
      final (c, p, session) = await _container(_FakeSource([MembershipProbe.notMember]));
      await c.read(deviceRemovalProvider.notifier).check();
      session.freshId = 'freshFamily3';
      await c.read(deviceRemovalProvider.notifier).parentSetUpAgain();
      expect(c.read(deviceRemovalProvider), isFalse);
      expect(p.containsKey(DeviceRemoval.removedKey), isFalse);
      expect(c.read(familyIdProvider), 'freshFamily3');
      expect(session.freshFamilies, 1);
    });
  });

  group('child safety: a removed child device stays locked', () {
    test('removedLockPolicy is locked with no minutes', () {
      final policy = removedLockPolicy(const AppSettings());
      expect(policy.locked, isTrue);
      expect(policy.reason, 'removed');
      expect(policy.remainingMinutes, 0);
    });

    test('a paused child device (unlocked on Free) becomes locked when removed', () async {
      // Worst case: on Free, a paired child that is not the free child is paused = no limits.
      final (c, _, _) = await _container(
        _FakeSource([MembershipProbe.notMember]),
        status: FamilyPlanStatus(createdAt: DateTime.utc(2026, 10, 1)),
      );
      expect(c.read(thisDevicePausedProvider), isTrue);
      expect(c.read(lockPolicyProvider).locked, isFalse); // precondition: unlocked before

      await c.read(deviceRemovalProvider.notifier).check();
      final policy = c.read(lockPolicyProvider);
      expect(policy.locked, isTrue);
      expect(policy.reason, 'removed');
    });

    test('the fresh unbound child on Free (daily limit left) stays locked too', () async {
      final (c, _, _) = await _container(
        _FakeSource([MembershipProbe.notMember]),
        prefs: {'settings.language': 'en', FamilyBootstrap.idKey: _oldFamilyId},
      );
      expect(c.read(lockPolicyProvider).locked, isFalse); // precondition: 60 free minutes left
      await c.read(deviceRemovalProvider.notifier).check();
      expect(c.read(lockPolicyProvider).locked, isTrue);
    });
  });

  group('removed-device screen', () {
    Future<(SharedPreferences, List<String>)> pump(WidgetTester tester, {required String lang}) async {
      SharedPreferences.setMockInitialValues({
        'settings.language': lang,
        'settings.pin': PinSecurity.hashPin('1234', rounds: 10),
        DeviceRemoval.removedKey: true,
      });
      final p = await SharedPreferences.getInstance();
      final done = <String>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(p),
          removalSessionProvider.overrideWithValue(
            RemovalSession(signOut: () async {}, startFreshFamily: (_) async => null),
          ),
        ],
        child: MaterialApp(
          locale: Locale(lang),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Same wiring as app.dart.
          builder: (context, child) => RemovedDeviceGate(onSetUpDone: () => done.add('done'), child: child!),
          home: const Scaffold(body: Text('CHILD HOME')),
        ),
      ));
      await tester.pumpAndSettle();
      return (p, done);
    }

    testWidgets('English: calm message, ask a parent, no app behind it', (tester) async {
      await pump(tester, lang: 'en');
      expect(find.byKey(const Key('removedDeviceScreen')), findsOneWidget);
      expect(find.text('This device was removed from the family'), findsOneWidget);
      expect(find.textContaining('Ask a parent'), findsOneWidget);
      expect(find.byKey(const Key('removedDeviceLockedNote')), findsOneWidget);
      expect(find.text('CHILD HOME'), findsNothing);
    });

    testWidgets('Arabic first: RTL title', (tester) async {
      await pump(tester, lang: 'ar');
      expect(find.text('هذا الجهاز أُزيل من العائلة'), findsOneWidget);
      final ctx = tester.element(find.byKey(const Key('removedDeviceScreen')));
      expect(Directionality.of(ctx), TextDirection.rtl);
    });

    testWidgets('a wrong PIN keeps the device removed and locked', (tester) async {
      final (p, done) = await pump(tester, lang: 'en');
      await tester.tap(find.byKey(const Key('removedDeviceParentButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '9999');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await tester.pumpAndSettle();
      expect(p.getBool(DeviceRemoval.removedKey), isTrue);
      expect(done, isEmpty);
      expect(find.text('CHILD HOME'), findsNothing);
    });

    testWidgets('the parent PIN sets the device up again and opens the parent area', (tester) async {
      final (p, done) = await pump(tester, lang: 'en');
      await tester.tap(find.byKey(const Key('removedDeviceParentButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), '1234');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
      await tester.pumpAndSettle();
      expect(p.containsKey(DeviceRemoval.removedKey), isFalse);
      expect(done, ['done']);
      expect(find.text('CHILD HOME'), findsOneWidget);
      final container = ProviderScope.containerOf(tester.element(find.text('CHILD HOME')));
      expect(container.read(parentUnlockedProvider), isTrue);
      expect(container.read(childrenProvider).children.single.id, ChildProfile.defaultId);
    });
  });
}
