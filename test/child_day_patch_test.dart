import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/family/family_repository.dart';

// R-32: a paired child device writes only what backend/firestore.rules `childDayWrite` allows.
FamilyDay dayWith(
  Map<String, TaskProgress> progress, {
  int used = 0,
  bool prayerLock = false,
  DateTime? since,
}) =>
    WalletState(
      day: '2026-11-22',
      tasks: defaultTasks,
      progress: progress,
      usedMinutes: used,
      prayerLock: prayerLock,
      prayerLockSince: since,
    ).toFamilyDay();

const _parentOnly = ['earnedMinutes', 'requiredDone', 'usedMinutes', 'updatedAt', 'updatedBy'];

void main() {
  test('submitting a task writes one pending entry and nothing parent-only', () {
    final before = dayWith({'homework': const TaskProgress(status: TaskStatus.done)});
    final after = dayWith({
      'homework': const TaskProgress(status: TaskStatus.done),
      'prayer': const TaskProgress(status: TaskStatus.pending),
    });
    final patches = ChildDayPatch.between(before, after);
    expect(patches, hasLength(1));
    final json = patches.single.toJson();
    expect(json['childTask'], 'prayer');
    expect(json['progress'], {
      'prayer': {'status': 'pending', 'count': 0},
    });
    for (final key in _parentOnly) {
      expect(json.containsKey(key), isFalse, reason: key);
    }
    expect(json.containsKey('prayerLock'), isFalse);
  });

  test('an approval made on the child device is never written', () {
    final before = dayWith({'homework': const TaskProgress(status: TaskStatus.pending)});
    final after = dayWith({'homework': const TaskProgress(status: TaskStatus.done)});
    expect(ChildDayPatch.between(before, after), isEmpty);
  });

  test('play time is sent only as a positive increment', () {
    final more = ChildDayPatch.between(dayWith({}, used: 5), dayWith({}, used: 12));
    expect(more.single.usedMinutesDelta, 7);
    expect(more.single.toJson().containsKey('usedMinutes'), isFalse);
    expect(ChildDayPatch.between(dayWith({}, used: 12), dayWith({}, used: 5)), isEmpty);
  });

  test('a child device starts a prayer lock but never ends it', () {
    final since = DateTime.utc(2026, 11, 22, 12, 5);
    final start = ChildDayPatch.between(
      dayWith({'prayer': const TaskProgress(status: TaskStatus.done)}),
      dayWith({'prayer': const TaskProgress()}, prayerLock: true, since: since),
    ).single.toJson();
    expect(start['prayerLock'], isTrue);
    expect(start['prayerLockSinceMs'], since.millisecondsSinceEpoch);
    expect(start['progress'], {
      'prayer': {'status': 'todo', 'count': 0},
    });

    final end = ChildDayPatch.between(dayWith({}, prayerLock: true, since: since), dayWith({}));
    expect(end, isEmpty);
  });

  test('several changed tasks become one write per task', () {
    final patches = ChildDayPatch.between(
      dayWith({}),
      dayWith({
        'prayer': const TaskProgress(status: TaskStatus.pending),
        'pushup': const TaskProgress(count: 3),
      }),
    );
    expect(patches.map((p) => p.taskId), ['prayer', 'pushup']);
    expect(patches.last.toJson()['progress'], {
      'pushup': {'status': 'todo', 'count': 3},
    });
  });

  test('no change means no write', () {
    final d = dayWith({'prayer': const TaskProgress(status: TaskStatus.pending)}, used: 3);
    expect(ChildDayPatch.between(d, d), isEmpty);
  });
}
