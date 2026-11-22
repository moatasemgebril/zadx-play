// "Excused today" (owner decision 2026-11-22; Dar al-Ifta al-Misriyya fatwa 7711
// https://dar-alifta.org/ar/fatwa/details/19049/ , Ibn Baz fatwa 13476): a parent-only, per-day,
// per-child pause of prayer tasks and the prayer lock. Firestore rules side:
// backend/functions/test/rules.test.js ("only a parent device pauses or resumes prayer").
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:zadx/services/family/children_controller.dart';
import 'package:zadx/services/family/family_repository.dart';

class _Repo extends LocalFamilyRepository {
  _Repo({this.synced = false});
  final bool synced;
  final remote = StreamController<FamilyDay>.broadcast();
  final pauses = <({String childId, String day, bool paused})>[];
  final notifications = <String>[];
  final approvals = <List<String>>[];

  @override
  bool get serverApprovals => synced;

  @override
  Stream<FamilyDay> watchDay(String childId, String day) => remote.stream;

  @override
  Future<void> setPrayerPaused({required String childId, required String day, required bool paused}) async =>
      pauses.add((childId: childId, day: day, paused: paused));

  @override
  Future<void> notifyParent(String childId, String type, {Map<String, Object?> data = const {}}) async =>
      notifications.add(type);

  @override
  Future<void> approveTask({
    required String childId,
    required String day,
    required String taskId,
    required int minutes,
    required List<String> requiredTaskIds,
    required bool isPrayer,
  }) async =>
      approvals.add(requiredTaskIds);
}

const today = '2026-11-20';

Future<(ProviderContainer, SharedPreferences, _Repo)> makeContainer({bool synced = false, bool childDevice = false}) async {
  SharedPreferences.setMockInitialValues({'settings.language': 'en'});
  final prefs = await SharedPreferences.getInstance();
  final repo = _Repo(synced: synced);
  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 20, 10), 2)),
    nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
    familyRepositoryProvider.overrideWithValue(repo),
  ]);
  if (synced) container.read(familyIdProvider.notifier).state = 'fam1';
  if (childDevice) {
    container.read(childrenProvider.notifier).bindTo(const ChildProfile(id: ChildProfile.defaultId, nickname: 'Sara', avatar: ChildAvatar.moon));
  }
  addTearDown(container.dispose);
  addTearDown(repo.remote.close);
  return (container, prefs, repo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paused: prayer tasks leave the day; required/progress/stars are not reduced', () {
    final base = WalletState(day: today, tasks: defaultTasks, progress: const {}, approved: const {'homework': 20});
    final paused = base.copyWith(prayerPaused: true);
    expect(base.requiredDone, isFalse); // prayer still required
    expect(paused.requiredDone, isTrue); // only homework is required today
    expect(paused.activeTasks.where((t) => t.kind == TaskKind.prayer), isEmpty);
    expect(paused.earnedMinutes, base.earnedMinutes); // nothing taken away
    expect(paused.doneCount, 1);
    expect(paused.gamesUnlocked, isTrue);
    // A pending "I prayed" is not shown to the parent while paused.
    final pending = paused.copyWith(progress: const {'prayer': TaskProgress(status: TaskStatus.pending)});
    expect(pending.pending, isEmpty);
  });

  test('paused round-trips through the saved day (today only: a new day starts unpaused)', () {
    final s = WalletState(day: today, tasks: defaultTasks, progress: const {}, prayerPaused: true);
    final json = s.toFamilyDay().toJson();
    expect(json['prayerPaused'], isTrue);
    expect(FamilyDay.fromJson(json).prayerPaused, isTrue);
    expect(WalletState(day: today, tasks: defaultTasks, progress: const {}).toFamilyDay().toJson().containsKey('prayerPaused'), isFalse);
  });

  test('parent pauses: running lock ends, no new lock at the adhan, no notification', () async {
    final (container, prefs, repo) = await makeContainer();
    final wallet = container.read(walletProvider.notifier);
    wallet.startPrayerLock(Prayer.dhuhr);
    expect(container.read(walletProvider).prayerLock, isTrue);
    repo.notifications.clear();

    expect(wallet.setPrayerPaused(true), isTrue);
    expect(container.read(walletProvider).prayerLock, isFalse);
    expect(container.read(walletProvider).prayerPaused, isTrue);

    wallet.startPrayerLock(Prayer.asr);
    expect(container.read(walletProvider).prayerLock, isFalse);
    expect(repo.notifications, isEmpty, reason: 'nothing goes to the family log');

    // Survives a restart today; a new day starts unpaused.
    expect(WalletController.restoreFrom(prefs, ChildProfile.defaultId, today).prayerPaused, isTrue);
    expect(WalletController.restoreFrom(prefs, ChildProfile.defaultId, '2026-11-21').prayerPaused, isFalse);

    expect(wallet.setPrayerPaused(false), isTrue);
    wallet.startPrayerLock(Prayer.asr);
    expect(container.read(walletProvider).prayerLock, isTrue);
  });

  test('synced family: a parent device writes the pause; a child device cannot', () async {
    final (parent, _, parentRepo) = await makeContainer(synced: true);
    expect(parent.read(walletProvider.notifier).setPrayerPaused(true), isTrue);
    expect(parentRepo.pauses.single, (childId: ChildProfile.defaultId, day: today, paused: true));
    // Approvals while paused do not list prayer as required (server requiredDone).
    parent.read(walletProvider.notifier).submit('homework');
    parent.read(walletProvider.notifier).approve('homework');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(parentRepo.approvals.last, isNot(contains('prayer')));

    final (child, _, childRepo) = await makeContainer(synced: true, childDevice: true);
    expect(child.read(walletProvider.notifier).setPrayerPaused(true), isFalse);
    expect(child.read(walletProvider).prayerPaused, isFalse);
    expect(childRepo.pauses, isEmpty);
  });

  test('child device follows the parent pause from the server', () async {
    final (container, _, repo) = await makeContainer(synced: true, childDevice: true);
    container.read(walletProvider);
    repo.remote.add(FamilyDay(day: today, progress: const {}, usedMinutes: 0, prayerLock: false, approved: const {}, prayerPaused: true));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(walletProvider).prayerPaused, isTrue);
    container.read(walletProvider.notifier).startPrayerLock(Prayer.maghrib);
    expect(container.read(walletProvider).prayerLock, isFalse);
  });

  test('wording: parent-only title; the child line gives no reason', () {
    final ar = jsonDecode(File('lib/l10n/app_ar.arb').readAsStringSync()) as Map<String, dynamic>;
    final en = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;
    expect(ar['prayerPauseTitle'], 'إيقاف مهام الصلاة مؤقتًا (عذر)');
    expect(en['prayerPauseTitle'], 'Pause prayer tasks (excused)');
    expect(ar['otherTasksOpenToday'], 'مهامّك الأخرى متاحة اليوم');
    expect(en['otherTasksOpenToday'], 'Your other tasks are open today');
    for (final word in ['عذر', 'حيض', 'excus', 'period']) {
      expect((ar['otherTasksOpenToday'] as String).contains(word), isFalse);
      expect((en['otherTasksOpenToday'] as String).toLowerCase().contains(word), isFalse);
    }
  });
}
