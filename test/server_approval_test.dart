import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/family/approval_queue.dart';
import 'package:zadx/services/family/children_controller.dart';
import 'package:zadx/services/family/family_repository.dart';

/// R-32: in a synced family only the server (approveTask, parent devices only) credits minutes.
class _ServerRepo extends LocalFamilyRepository {
  final remote = StreamController<FamilyDay>.broadcast();
  final approvals = <Map<String, Object?>>[];
  final rejections = <String>[];
  final saves = <({FamilyDay day, bool lockChanged})>[];
  Object? failWith;

  @override
  bool get serverApprovals => true;

  @override
  Stream<FamilyDay> watchDay(String childId, String day) => remote.stream;

  @override
  Future<void> saveDay(String childId, FamilyDay day, {bool lockChanged = false}) async =>
      saves.add((day: day, lockChanged: lockChanged));

  @override
  Future<void> approveTask({
    required String childId,
    required String day,
    required String taskId,
    required int minutes,
    required List<String> requiredTaskIds,
    required bool isPrayer,
  }) async {
    if (failWith != null) throw failWith!;
    approvals.add({'childId': childId, 'day': day, 'taskId': taskId, 'minutes': minutes, 'isPrayer': isPrayer, 'required': requiredTaskIds});
  }

  @override
  Future<void> rejectTask({required String childId, required String day, required String taskId}) async {
    if (failWith != null) throw failWith!;
    rejections.add(taskId);
  }
}

const today = '2026-11-20';

Future<(ProviderContainer, SharedPreferences, _ServerRepo)> makeContainer({bool childDevice = false}) async {
  SharedPreferences.setMockInitialValues({'settings.language': 'en'});
  final prefs = await SharedPreferences.getInstance();
  final repo = _ServerRepo();
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 20, 10), 2)),
    nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
    familyRepositoryProvider.overrideWithValue(repo),
  ]);
  container.read(familyIdProvider.notifier).state = 'fam1';
  if (childDevice) {
    container.read(childrenProvider.notifier).bindTo(const ChildProfile(id: ChildProfile.defaultId, nickname: 'Sara', avatar: ChildAvatar.moon));
  }
  addTearDown(container.dispose);
  addTearDown(repo.remote.close);
  return (container, prefs, repo);
}

FamilyDay serverDay({Map<String, int> approved = const {}, Map<String, String> statuses = const {}, bool lock = false}) => FamilyDay(
      day: today,
      progress: {for (final e in statuses.entries) e.key: {'status': e.value, 'count': 0}},
      usedMinutes: 0,
      prayerLock: lock,
      approved: approved,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a child device marking tasks "done" earns nothing without server credits', () {
    final s = WalletState(
      day: today,
      tasks: defaultTasks,
      progress: const {'prayer': TaskProgress(status: TaskStatus.done), 'homework': TaskProgress(status: TaskStatus.done)},
      approved: const {},
    );
    expect(s.earnedMinutes, 0);
    expect(s.requiredDone, isFalse);
    expect(s.gamesUnlocked, isFalse);
    final credited = WalletState(day: today, tasks: defaultTasks, progress: const {}, approved: const {'prayer': 10, 'homework': 20});
    expect(credited.earnedMinutes, 30);
    expect(credited.requiredDone, isTrue);
    expect(credited.gamesUnlocked, isTrue);
  });

  test('child device: submit syncs a pending submission; approve and reject are refused', () async {
    final (container, _, repo) = await makeContainer(childDevice: true);
    final wallet = container.read(walletProvider.notifier);
    wallet.submit('homework');
    expect(repo.saves.last.day.progress['homework']?['status'], 'pending');
    expect(repo.saves.last.lockChanged, isFalse);

    expect(wallet.canApprove, isFalse);
    expect(wallet.approve('homework'), isFalse);
    expect(wallet.reject('homework'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(repo.approvals, isEmpty);
    expect(container.read(walletProvider).earnedMinutes, 0);
  });

  test('child device: minutes arrive only from the server snapshot', () async {
    final (container, _, repo) = await makeContainer(childDevice: true);
    container.read(walletProvider); // subscribe
    repo.remote.add(serverDay(approved: {'prayer': 10, 'homework': 20}, statuses: {'prayer': 'done', 'homework': 'done'}));
    await Future<void>.delayed(Duration.zero);
    final s = container.read(walletProvider);
    expect(s.earnedMinutes, 30);
    expect(s.gamesUnlocked, isTrue);
  });

  test('parent device: approve calls the server with the task minutes and required list', () async {
    final (container, _, repo) = await makeContainer();
    final wallet = container.read(walletProvider.notifier);
    wallet.submit('homework');
    expect(wallet.approve('homework'), isTrue);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(repo.approvals.single['taskId'], 'homework');
    expect(repo.approvals.single['minutes'], 20);
    expect(repo.approvals.single['isPrayer'], false);
    expect(repo.approvals.single['required'], containsAll(['prayer', 'homework']));
    // Optimistic on the parent phone until the server snapshot arrives.
    expect(container.read(walletProvider).isApproved('homework'), isTrue);
  });

  test('parent device: approving "I prayed" ends the lock and syncs the lock change', () async {
    final (container, _, repo) = await makeContainer();
    final wallet = container.read(walletProvider.notifier);
    wallet.startPrayerLock(Prayer.asr);
    expect(repo.saves.last.lockChanged, isTrue);
    expect(repo.saves.last.day.prayerLock, isTrue);
    wallet.markPrayed();
    expect(wallet.approve('prayer'), isTrue);
    expect(container.read(walletProvider).prayerLock, isFalse);
    expect(repo.saves.last.lockChanged, isTrue);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(repo.approvals.single['isPrayer'], true);
  });

  test('saved days never carry server-only credits as a lock change', () async {
    final (container, _, repo) = await makeContainer(childDevice: true);
    final wallet = container.read(walletProvider.notifier);
    wallet.submit('room');
    expect(repo.saves.every((s) => !s.lockChanged), isTrue);
  });

  test('offline approvals are queued and sent later; refused ones are dropped', () async {
    final (container, prefs, repo) = await makeContainer();
    final wallet = container.read(walletProvider.notifier);
    repo.failWith = Exception('offline');
    wallet.approve('homework');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final queue = ApprovalQueue(prefs);
    expect(queue.read().single.taskId, 'homework');

    repo.failWith = null;
    await queue.flush(repo, 'fam1');
    expect(queue.read(), isEmpty);
    expect(repo.approvals.single['taskId'], 'homework');

    // Refused for good (e.g. this phone was turned into a child device): not retried forever.
    repo.failWith = const ApprovalRejected('permission-denied');
    queue.add(const PendingApproval(approve: true, familyId: 'fam1', childId: 'child-1', day: today, taskId: 'room'));
    await queue.flush(repo, 'fam1');
    expect(queue.read(), isEmpty);

    // Decisions queued for another family are dropped, never sent to the new one.
    repo.failWith = null;
    queue.add(const PendingApproval(approve: true, familyId: 'old', childId: 'child-1', day: today, taskId: 'room'));
    await queue.flush(repo, 'fam1');
    expect(queue.read(), isEmpty);
    expect(repo.approvals.length, 1);
  });
}
