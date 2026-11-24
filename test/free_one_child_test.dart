import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/parent/children_card.dart';
import 'package:zadx/features/parent/paused_child_screen.dart';
import 'package:zadx/features/parent/pin_security.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';
import 'package:zadx/services/app_lock/app_lock_service.dart';
import 'package:zadx/services/billing/subscription_service.dart';
import 'package:zadx/services/billing/trial_clock.dart';
import 'package:zadx/services/family/child_pause.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/children_controller.dart';

/// Free plan = ONE child (owner decision 2026-11-21, docs/decisions/FREE-ONE-CHILD.md).

const _free = Entitlement();
const _plus = Entitlement(tier: PlanTier.plus);

/// The plan the test container sees; tests switch it to simulate subscribing / expiring.
final _testPlan = StateProvider<Entitlement>((_) => _free);

Future<(ProviderContainer, SharedPreferences)> _container({Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues({'settings.language': 'en', ...prefs});
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(p),
    cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 21, 10), 2)),
    nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
    clockProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 11, 21, 8))),
    planEntitlementProvider.overrideWith((ref) => ref.watch(_testPlan)),
  ]);
  addTearDown(c.dispose);
  return (c, p);
}

const _kids = [
  ChildProfile(id: ChildProfile.defaultId, nickname: 'Sara'),
  ChildProfile(id: 'cyusuf', nickname: 'Yusuf'),
  ChildProfile(id: 'cmaryam', nickname: 'Maryam'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pause rule (pure)', () {
    test('Free: the first child stays active, the others are paused', () {
      final p = childPauseFor(children: _kids, multipleChildrenAllowed: false);
      expect(p.freeChildId, ChildProfile.defaultId);
      expect(p.pausedIds, {'cyusuf', 'cmaryam'});
      expect(p.anyPaused, isTrue);
    });

    test('Free: the child the parent chose stays active instead', () {
      final p = childPauseFor(children: _kids, multipleChildrenAllowed: false, chosenFreeChildId: 'cmaryam');
      expect(p.freeChildId, 'cmaryam');
      expect(p.pausedIds, {ChildProfile.defaultId, 'cyusuf'});
    });

    test('a removed choice falls back to the first child', () {
      final p = childPauseFor(children: _kids, multipleChildrenAllowed: false, chosenFreeChildId: 'cgone');
      expect(p.freeChildId, ChildProfile.defaultId);
    });

    test('paid plans and trials pause nobody', () {
      final p = childPauseFor(children: _kids, multipleChildrenAllowed: true, chosenFreeChildId: 'cmaryam');
      expect(p.pausedIds, isEmpty);
    });

    test('one child is never paused', () {
      final p = childPauseFor(children: [_kids.first], multipleChildrenAllowed: false);
      expect(p.pausedIds, isEmpty);
    });

    test('a shared device never shows a paused child', () {
      final p = childPauseFor(children: _kids, multipleChildrenAllowed: false);
      expect(effectiveActiveChildId(selected: 'cyusuf', pause: p), ChildProfile.defaultId);
      expect(effectiveActiveChildId(selected: ChildProfile.defaultId, pause: p), ChildProfile.defaultId);
    });
  });

  group('FamilyPlanStatus (child devices; same rule as the server)', () {
    final now = DateTime.utc(2026, 12, 10, 12);
    final monthAgo = now.subtract(const Duration(days: 30));

    test('Free after the first 7 days: only child-1 (or the chosen child) is active', () {
      final s = FamilyPlanStatus(createdAt: monthAgo);
      expect(s.childPaused(ChildProfile.defaultId, now), isFalse);
      expect(s.childPaused('cyusuf', now), isTrue);
      final chosen = FamilyPlanStatus(createdAt: monthAgo, freeChildId: 'cyusuf');
      expect(chosen.childPaused('cyusuf', now), isFalse);
      expect(chosen.childPaused(ChildProfile.defaultId, now), isTrue);
    });

    test('a paid plan or the family trial resumes everyone; expiry pauses again', () {
      expect(
        FamilyPlanStatus(plan: PlanTier.basic, planExpiresAt: now.add(const Duration(days: 3)), createdAt: monthAgo)
            .childPaused('cyusuf', now),
        isFalse,
      );
      expect(
        FamilyPlanStatus(plan: PlanTier.plus, planExpiresAt: now.subtract(const Duration(minutes: 1)), createdAt: monthAgo)
            .childPaused('cyusuf', now),
        isTrue,
      );
      expect(FamilyPlanStatus(createdAt: now.subtract(const Duration(days: 6))).childPaused('cyusuf', now), isFalse);
      expect(FamilyPlanStatus(createdAt: now.subtract(const Duration(days: 7))).childPaused('cyusuf', now), isTrue);
    });

    test('reads the family doc safely and survives the on-device cache', () {
      final s = FamilyPlanStatus.fromFamilyDoc({
        'plan': 'plus',
        'planExpiresAt': '2027-01-01T00:00:00.000Z',
        'createdAt': monthAgo.millisecondsSinceEpoch,
        'freeChildId': 'cyusuf',
      });
      expect(s.plan, PlanTier.plus);
      expect(FamilyPlanStatus.tryDecode(s.encode()), s);

      final bad = FamilyPlanStatus.fromFamilyDoc({'plan': 'gold', 'freeChildId': '../x', 'createdAt': 'x'});
      expect(bad.plan, isNull); // unknown = Free, never paid
      expect(bad.freeChildId, isNull);
      expect(bad.createdAt, isNull);
      expect(FamilyPlanStatus.tryDecode('not json ['), isNull);
    });
  });

  group('parent / shared device', () {
    Future<(ProviderContainer, SharedPreferences, ChildrenController)> family3() async {
      final (c, p) = await _container();
      c.read(_testPlan.notifier).state = _plus; // children added during the trial / a paid plan
      final kids = c.read(childrenProvider.notifier);
      expect(kids.add('Yusuf', ChildAvatar.rocket, maxChildren: 5), AddChildResult.added);
      expect(kids.add('Maryam', ChildAvatar.flower, maxChildren: 5), AddChildResult.added);
      return (c, p, kids);
    }

    test('dropping to Free pauses the others, keeps their data, and subscribing resumes them', () async {
      final (c, p, kids) = await family3();
      final yusuf = c.read(childrenProvider).children[1].id;

      // Yusuf earns some progress while the family has the trial.
      expect(kids.select(yusuf), isTrue);
      c.read(walletProvider.notifier).approve('prayer');
      final saved = p.getString(ChildStorage.walletKey(yusuf));
      expect(saved, isNotNull);

      // Trial ends: Free.
      c.read(_testPlan.notifier).state = _free;
      final pause = c.read(childPauseProvider);
      expect(pause.freeChildId, ChildProfile.defaultId);
      expect(pause.isPaused(yusuf), isTrue);
      expect(c.read(activeChildIdProvider), ChildProfile.defaultId); // never shows a paused child
      expect(kids.select(yusuf), isFalse); // and cannot select one

      // Nothing was deleted.
      expect(c.read(childrenProvider).children.length, 3);
      expect(p.getString(ChildStorage.walletKey(yusuf)), saved);

      // The family subscribes: everyone is active again, Yusuf's progress is still there.
      c.read(_testPlan.notifier).state = _plus;
      expect(c.read(childPauseProvider).pausedIds, isEmpty);
      expect(kids.select(yusuf), isTrue);
      expect(c.read(activeChildIdProvider), yusuf);
      expect(c.read(walletProvider).progressOf('prayer').status, TaskStatus.done);
    });

    test('the parent chooses which child stays active on Free (stored, survives restart)', () async {
      final (c, p, kids) = await family3();
      c.read(_testPlan.notifier).state = _free;
      final maryam = c.read(childrenProvider).children[2].id;

      expect(kids.chooseFreeChild(maryam), isTrue);
      expect(c.read(childPauseProvider).freeChildId, maryam);
      expect(c.read(childPauseProvider).isPaused(ChildProfile.defaultId), isTrue);
      expect(c.read(activeChildIdProvider), maryam);
      expect(p.getString(ChildStorage.freeChildKey), maryam);

      // A fresh start reads the same choice.
      final again = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 21, 10), 2)),
        nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
        planEntitlementProvider.overrideWithValue(_free),
      ]);
      addTearDown(again.dispose);
      expect(again.read(activeChildIdProvider), maryam);

      expect(kids.chooseFreeChild('cunknown'), isFalse);
    });

    test('removing the chosen child falls back to the first child', () async {
      final (c, p, kids) = await family3();
      c.read(_testPlan.notifier).state = _free;
      final maryam = c.read(childrenProvider).children[2].id;
      kids.chooseFreeChild(maryam);
      expect(kids.remove(maryam), isTrue);
      expect(c.read(childPauseProvider).freeChildId, ChildProfile.defaultId);
      expect(p.getString(ChildStorage.freeChildKey), isNull);
    });
  });

  group('paired child device', () {
    Future<ProviderContainer> boundTo(String childId, FamilyPlanStatus? status) async {
      SharedPreferences.setMockInitialValues({'settings.language': 'en'});
      final p = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(p),
        cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 21, 10), 2)),
        nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
        clockProvider.overrideWith((ref) => Stream.value(DateTime.utc(2026, 11, 21, 8))),
        planEntitlementProvider.overrideWithValue(_free),
        familyPlanStatusProvider.overrideWith((ref) => Stream.value(status)),
      ]);
      addTearDown(c.dispose);
      c.read(childrenProvider.notifier).bindTo(ChildProfile(id: childId, nickname: 'Kid'));
      await c.read(familyPlanStatusProvider.future);
      await c.read(clockProvider.future);
      return c;
    }

    final monthOld = FamilyPlanStatus(createdAt: DateTime.utc(2026, 10, 1));

    test('a paused child device has no time limit outside prayer', () async {
      final c = await boundTo('cyusuf', monthOld);
      expect(c.read(thisDevicePausedProvider), isTrue);
      expect(c.read(activeChildIdProvider), 'cyusuf'); // its data stays its own

      final policy = pausedLockPolicy(c.read(settingsProvider));
      expect(policy.locked, isFalse);
      expect(policy.reason, 'paused');
      expect(policy.remainingMinutes, greaterThan(0)); // never "out of minutes"
    });

    group('adhan lock on a paused device (owner decision 2026-11-24)', () {
      final since = DateTime.utc(2026, 11, 21, 8);
      final prayerWallet = WalletState(
        day: '2026-11-21',
        tasks: const [],
        progress: const {},
        prayerLock: true,
        lockedPrayer: Prayer.dhuhr,
        prayerLockSince: since,
      );

      test('locks games during the Free prayer window', () async {
        final c = await boundTo('cyusuf', monthOld);
        final policy = pausedLockPolicy(c.read(settingsProvider),
            wallet: prayerWallet, now: since.add(const Duration(minutes: 5)));
        expect(policy.locked, isTrue);
        expect(policy.reason, 'prayer');
        expect(policy.prayerAutoEndMinutes, freePrayerLockWindow.inMinutes);
        expect(policy.prayerLockSinceMs, since.millisecondsSinceEpoch);
      });

      test('unlocks by itself after the prayer window', () async {
        final c = await boundTo('cyusuf', monthOld);
        final policy = pausedLockPolicy(c.read(settingsProvider),
            wallet: prayerWallet, now: since.add(freePrayerLockWindow + const Duration(minutes: 1)));
        expect(policy.locked, isFalse);
        expect(policy.reason, 'paused');
      });

      test('follows the parent "lock at adhan" setting', () async {
        final c = await boundTo('cyusuf', monthOld);
        final off = c.read(settingsProvider).copyWith(lockAtAdhan: false);
        final policy = pausedLockPolicy(off, wallet: prayerWallet, now: since.add(const Duration(minutes: 5)));
        expect(policy.locked, isFalse);
      });

      test('the live policy of a paused device uses the prayer lock', () async {
        final c = await boundTo('cyusuf', monthOld);
        expect(c.read(thisDevicePausedProvider), isTrue);
        final policy = c.read(lockPolicyProvider);
        expect(policy.reason, anyOf('paused', 'prayer'));
        expect(policy.prayerAutoEndMinutes, freePrayerLockWindow.inMinutes);
      });
    });

    test('the free child device stays locked as usual', () async {
      final c = await boundTo(ChildProfile.defaultId, monthOld);
      expect(c.read(thisDevicePausedProvider), isFalse);
    });

    test('unknown family status is the safe default: not paused, so still locked', () async {
      final c = await boundTo('cyusuf', null);
      expect(c.read(thisDevicePausedProvider), isFalse);
    });

    test('the family subscribing resumes a paused child device', () async {
      final paid = FamilyPlanStatus(
        plan: PlanTier.basic,
        planExpiresAt: DateTime.utc(2027, 1, 1),
        createdAt: DateTime.utc(2026, 10, 1),
      );
      final c = await boundTo('cyusuf', paid);
      expect(c.read(thisDevicePausedProvider), isFalse);
    });
  });

  group('assistant needs a verified paid plan', () {
    test('hidden during the on-device trial, shown for verified plans', () {
      final trial = resolveEntitlement(
        trial: TrialStatus(
          startedAt: DateTime.utc(2026, 11, 21),
          endsAt: DateTime.utc(2026, 11, 28),
          active: true,
          daysLeft: 7,
        ),
      );
      expect(trial.deviceTrial, isTrue);
      expect(hasFeature(trial, AppFeature.multipleChildren), isTrue); // the trial still opens everything else
      expect(assistantAvailable(trial), isFalse);

      expect(assistantAvailable(const Entitlement(tier: PlanTier.basic)), isTrue);
      expect(assistantAvailable(const Entitlement(tier: PlanTier.plus, inTrial: true)), isTrue); // store trial
      expect(assistantAvailable(_free), isFalse);
    });
  });

  group('screens', () {
    Future<void> pumpCard(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({'settings.language': 'en'});
      final p = await SharedPreferences.getInstance();
      ChildStorage.writeChildren(p, _kids);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(p),
          cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 21, 10), 2)),
          nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
          planEntitlementProvider.overrideWithValue(_free),
          entitlementProvider.overrideWith((ref) => Stream.value(_free)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SingleChildScrollView(child: ChildrenCard())),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the parent sees paused children greyed with "subscribe to resume"', (tester) async {
      await pumpCard(tester);
      expect(find.byKey(const Key('childPaused-cyusuf')), findsOneWidget);
      expect(find.byKey(const Key('childPaused-cmaryam')), findsOneWidget);
      expect(find.byKey(const Key('childPaused-child-1')), findsNothing);
      expect(find.byKey(const Key('chooseFreeChildButton')), findsOneWidget);
    });

    testWidgets('choosing the active child asks for the PIN first', (tester) async {
      await pumpCard(tester);
      await tester.ensureVisible(find.byKey(const Key('chooseFreeChildButton')));
      await tester.tap(find.byKey(const Key('chooseFreeChildButton')));
      await tester.pumpAndSettle();
      // No PIN stored in this test, so confirmParentPin refuses and nothing changes.
      expect(find.byKey(const Key('freeChild-cyusuf')), findsNothing);
    });

    testWidgets('the paused child screen is kid-safe: no price, ask a parent behind the PIN', (tester) async {
      SharedPreferences.setMockInitialValues({'settings.pin': PinSecurity.hashPin('1234', rounds: 10)});
      final p = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(p)],
        child: MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PausedChildScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining(r'$'), findsNothing);
      await tester.tap(find.byKey(const Key('pausedAskParentButton')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget); // PIN prompt
      expect(find.byKey(const Key('seePlansButton')), findsNothing);
    });
  });
}
