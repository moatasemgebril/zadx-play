import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/billing/subscription_service.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/children_controller.dart';

const today = '2026-11-20';

Future<(ProviderContainer, SharedPreferences)> makeContainer(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues({'settings.language': 'en', ...initial});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 20, 10), 2)),
    nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
    // A paid plan: these tests are about several children (Free pauses all but one,
    // see test/free_one_child_test.dart).
    planEntitlementProvider.overrideWithValue(const Entitlement(tier: PlanTier.plus)),
  ]);
  addTearDown(container.dispose);
  return (container, prefs);
}

String legacyDay({required String day, required Map<String, String> statuses, int used = 0}) => jsonEncode({
      'day': day,
      'progress': {for (final e in statuses.entries) e.key: {'status': e.value, 'count': 0}},
      'usedMinutes': used,
      'prayerLock': false,
      'earnedMinutes': 0,
      'requiredDone': false,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('migration from single-child data', () {
    test('existing wallet, tasks and adhkar move into the default child', () async {
      final legacyWallet = legacyDay(day: today, statuses: {'prayer': 'done', 'homework': 'pending'}, used: 5);
      final legacyTasks = jsonEncode(
        [TaskDefinition.fromJson(_customTaskJson('read', 15)).toJson()],
      );
      const legacyAdhkar = '{"day":"2026-11-20","counts":{"x":3}}';
      final (container, prefs) = await makeContainer({
        ChildStorage.legacyWalletKey: legacyWallet,
        ChildStorage.legacyTasksKey: legacyTasks,
        ChildStorage.legacyAdhkarKey: legacyAdhkar,
      });

      final children = container.read(childrenProvider);
      expect(children.children.map((c) => c.id), [ChildProfile.defaultId]);
      expect(children.activeId, ChildProfile.defaultId);
      expect(children.isBound, isFalse);

      // Data now lives under the default child, legacy keys are gone.
      expect(prefs.getString(ChildStorage.walletKey(ChildProfile.defaultId)), legacyWallet);
      expect(prefs.getString(ChildStorage.tasksKey(ChildProfile.defaultId)), legacyTasks);
      expect(prefs.getString(ChildStorage.adhkarKey(ChildProfile.defaultId)), legacyAdhkar);
      expect(prefs.getString(ChildStorage.legacyWalletKey), isNull);
      expect(prefs.getString(ChildStorage.legacyTasksKey), isNull);
      expect(prefs.getString(ChildStorage.legacyAdhkarKey), isNull);

      // Nobody loses progress: the wallet shows the same day as before.
      final wallet = container.read(walletProvider);
      expect(wallet.tasks.map((t) => t.id), ['read']);
      expect(wallet.progressOf('prayer').status, TaskStatus.done);
      expect(wallet.progressOf('homework').status, TaskStatus.pending);
      expect(wallet.usedMinutes, 5);
    });

    test('migration is idempotent and keeps later per-child data', () async {
      final (_, prefs) = await makeContainer({
        ChildStorage.legacyWalletKey: legacyDay(day: today, statuses: {'prayer': 'done'}),
      });
      final first = ChildStorage.migrate(prefs);
      prefs.setString(ChildStorage.walletKey(ChildProfile.defaultId), legacyDay(day: today, statuses: {}, used: 9));
      final second = ChildStorage.migrate(prefs);
      expect(second, first);
      final restored = WalletController.restoreFrom(prefs, ChildProfile.defaultId, today);
      expect(restored.usedMinutes, 9);
    });

    test('fresh install gets one default child with default tasks', () async {
      final (container, _) = await makeContainer({});
      final children = container.read(childrenProvider);
      expect(children.children.single.id, ChildProfile.defaultId);
      expect(children.children.single.nickname, isEmpty);
      expect(container.read(walletProvider).progress, isEmpty);
    });

    test('corrupted children list falls back to a default child', () async {
      final (container, _) = await makeContainer({ChildStorage.childrenKey: 'not json ['});
      expect(container.read(childrenProvider).children.single.id, ChildProfile.defaultId);
    });

    test('invalid stored ids are dropped', () async {
      final (container, _) = await makeContainer({
        ChildStorage.childrenKey: jsonEncode([
          {'id': 'child-1', 'nickname': 'Sara', 'avatar': 'moon'},
          {'id': '../../etc', 'nickname': 'x'},
          {'id': 'child-1', 'nickname': 'dup'},
        ]),
      });
      final children = container.read(childrenProvider).children;
      expect(children.length, 1);
      expect(children.single.nickname, 'Sara');
      expect(children.single.avatar, ChildAvatar.moon);
    });
  });

  group('per-child wallet isolation', () {
    test('tasks, minutes and prayer lock belong to one child only', () async {
      final (container, prefs) = await makeContainer({});
      final kids = container.read(childrenProvider.notifier);
      expect(kids.add('Yusuf', ChildAvatar.rocket, maxChildren: planPlus.maxChildren), AddChildResult.added);
      final yusuf = container.read(childrenProvider).children.last.id;

      // Child 1: approve prayer + homework, use some minutes, then a prayer lock.
      final wallet = container.read(walletProvider.notifier);
      wallet.approve('prayer');
      wallet.approve('homework');
      expect(wallet.consumeMinutes(10), 10);
      wallet.startPrayerLock(Prayer.asr);
      wallet.removeTask('pushup');
      final first = container.read(walletProvider);
      expect(first.prayerLock, isTrue);
      expect(first.usedMinutes, 10);

      // Switch to Yusuf: a clean wallet with the default task list.
      kids.select(yusuf);
      final second = container.read(walletProvider);
      expect(second.progress, isEmpty);
      expect(second.usedMinutes, 0);
      expect(second.prayerLock, isFalse);
      expect(second.tasks.any((t) => t.id == 'pushup'), isTrue);

      container.read(walletProvider.notifier).submit('homework');
      expect(container.read(walletProvider).progressOf('homework').status, TaskStatus.pending);

      // Back to child 1: nothing from Yusuf leaked in.
      kids.select(ChildProfile.defaultId);
      final back = container.read(walletProvider);
      expect(back.progressOf('homework').status, TaskStatus.done);
      expect(back.usedMinutes, 10);
      expect(back.prayerLock, isTrue);
      expect(back.tasks.any((t) => t.id == 'pushup'), isFalse);

      // Stored separately on disk too.
      final storedYusuf = WalletController.restoreFrom(prefs, yusuf, today);
      expect(storedYusuf.progressOf('homework').status, TaskStatus.pending);
      expect(storedYusuf.usedMinutes, 0);
    });

    test('removing a child deletes only its data and switches away from it', () async {
      final (container, prefs) = await makeContainer({});
      final kids = container.read(childrenProvider.notifier);
      kids.add('Maryam', ChildAvatar.flower, maxChildren: 5);
      final maryam = container.read(childrenProvider).children.last.id;
      kids.select(maryam);
      expect(container.read(walletProvider).progress, isEmpty);
      container.read(walletProvider.notifier).approve('prayer');
      expect(prefs.getString(ChildStorage.walletKey(maryam)), isNotNull);

      expect(kids.remove(maryam), isTrue);
      expect(prefs.getString(ChildStorage.walletKey(maryam)), isNull);
      expect(container.read(childrenProvider).activeId, ChildProfile.defaultId);
      expect(container.read(walletProvider).progressOf('prayer').status, TaskStatus.todo);

      // The last child can never be removed.
      expect(kids.remove(ChildProfile.defaultId), isFalse);
    });
  });

  group('plan limits', () {
    test('Basic allows up to 2 children, Plus up to 5', () async {
      expect(planBasic.maxChildren, 2);
      expect(planPlus.maxChildren, 5);

      final (container, _) = await makeContainer({});
      final kids = container.read(childrenProvider.notifier);
      expect(kids.add('Ali', ChildAvatar.sun, maxChildren: planBasic.maxChildren), AddChildResult.added);
      expect(kids.add('Huda', ChildAvatar.moon, maxChildren: planBasic.maxChildren), AddChildResult.limitReached);
      expect(container.read(childrenProvider).children.length, 2);

      for (final name in ['Huda', 'Omar', 'Zaid']) {
        expect(kids.add(name, ChildAvatar.star, maxChildren: planPlus.maxChildren), AddChildResult.added);
      }
      expect(kids.add('Six', ChildAvatar.star, maxChildren: planPlus.maxChildren), AddChildResult.limitReached);
      expect(container.read(childrenProvider).children.length, 5);
    });

    test('canAddChild', () {
      expect(canAddChild(currentCount: 1, maxChildren: 2), isTrue);
      expect(canAddChild(currentCount: 2, maxChildren: 2), isFalse);
      expect(canAddChild(currentCount: 4, maxChildren: 5), isTrue);
      expect(canAddChild(currentCount: 5, maxChildren: 5), isFalse);
    });
  });

  group('child profile data minimisation', () {
    test('nicknames are trimmed, limited and reject contact details', () {
      expect(ChildProfile.cleanNickname('  Sara  '), 'Sara');
      expect(ChildProfile.cleanNickname('   '), isNull);
      expect(ChildProfile.cleanNickname('sara@example.com'), isNull);
      expect(ChildProfile.cleanNickname('Sara 01012345678'), isNull);
      expect(ChildProfile.cleanNickname('A' * 50)!.length, ChildProfile.maxNicknameLength);
      expect(ChildProfile.cleanNickname('يوسف'), 'يوسف');
    });

    test('profile json holds only id, nickname and avatar', () {
      const c = ChildProfile(id: 'c1', nickname: 'Sara', avatar: ChildAvatar.moon);
      expect(c.toJson().keys.toSet(), {'id', 'nickname', 'avatar'});
      expect(ChildProfile.isValidId(ChildProfile.newId()), isTrue);
    });

    test('rename rejects invalid nicknames', () async {
      final (container, _) = await makeContainer({});
      final kids = container.read(childrenProvider.notifier);
      expect(kids.edit(ChildProfile.defaultId, nickname: 'Noor', avatar: ChildAvatar.kitten), isTrue);
      expect(kids.edit(ChildProfile.defaultId, nickname: 'a@b.c', avatar: ChildAvatar.kitten), isFalse);
      expect(container.read(childrenProvider).active.nickname, 'Noor');
      expect(kids.add('', ChildAvatar.star, maxChildren: 5), AddChildResult.invalidName);
    });
  });

  test('a paired child device is bound to one child', () async {
    final (container, _) = await makeContainer({});
    final kids = container.read(childrenProvider.notifier);
    kids.bindTo(const ChildProfile(id: 'cabc', nickname: 'Amina', avatar: ChildAvatar.star));
    final s = container.read(childrenProvider);
    expect(s.isBound, isTrue);
    expect(s.activeId, 'cabc');
    kids.select(ChildProfile.defaultId);
    expect(container.read(childrenProvider).activeId, 'cabc');
    expect(kids.add('X', ChildAvatar.star, maxChildren: 5), AddChildResult.notAllowed);
    expect(kids.remove(ChildProfile.defaultId), isFalse);
  });
}

Map<String, dynamic> _customTaskJson(String id, int minutes) => {
      'id': id,
      'titleAr': 'قراءة',
      'titleEn': 'Reading',
      'subAr': '',
      'subEn': '',
      'kind': 'custom',
      'rewardMinutes': minutes,
      'color': 0xFF6C3BEB,
      'required': false,
      'reps': null,
    };
