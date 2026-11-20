import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/data/catalog/surah_index.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/referral/referral_service.dart';

WalletState stateWith(Map<String, TaskStatus> statuses, {int used = 0, bool prayerLock = false}) => WalletState(
      day: '2026-11-20',
      tasks: defaultTasks,
      progress: statuses.map((k, v) => MapEntry(k, TaskProgress(status: v))),
      usedMinutes: used,
      prayerLock: prayerLock,
    );

void main() {
  test('games stay locked until all must-do tasks are approved', () {
    final s = stateWith({'prayer': TaskStatus.done, 'homework': TaskStatus.pending});
    expect(s.requiredDone, isFalse);
    expect(s.gamesUnlocked, isFalse);
    expect(s.lockReason, LockReason.requiredTasks);
  });

  test('approved tasks earn minutes and unlock games', () {
    final s = stateWith({'prayer': TaskStatus.done, 'homework': TaskStatus.done, 'pushup': TaskStatus.done});
    expect(s.earnedMinutes, 10 + 20 + 10);
    expect(s.gamesUnlocked, isTrue);
  });

  test('pending tasks do not count until approved', () {
    final s = stateWith({'prayer': TaskStatus.done, 'homework': TaskStatus.done, 'falaq': TaskStatus.pending});
    expect(s.earnedMinutes, 30);
    expect(s.pending.map((t) => t.id), ['falaq']);
  });

  test('prayer lock overrides everything', () {
    final s = stateWith({'prayer': TaskStatus.done, 'homework': TaskStatus.done}, prayerLock: true);
    expect(s.gamesUnlocked, isFalse);
    expect(s.lockReason, LockReason.prayer);
  });

  test('used minutes lock games when the balance is zero', () {
    final s = stateWith({'prayer': TaskStatus.done, 'homework': TaskStatus.done}, used: 30);
    expect(s.remainingMinutes, 0);
    expect(s.lockReason, LockReason.noTime);
  });

  test('referral rewards: 1→2, 2→4, 3→6 months, capped at 3 friends', () {
    expect(const ReferralStatus(code: 'X', paidFriends: 0).rewardMonths, 0);
    expect(const ReferralStatus(code: 'X', paidFriends: 1).rewardMonths, 2);
    expect(const ReferralStatus(code: 'X', paidFriends: 2).rewardMonths, 4);
    expect(const ReferralStatus(code: 'X', paidFriends: 3).rewardMonths, 6);
    expect(const ReferralStatus(code: 'X', paidFriends: 9).rewardMonths, 6);
  });

  test('Quran index covers Juz 29 (67–77) and Juz 30 (78–114)', () {
    expect(surahsOfJuz(29).map((s) => s.number), List.generate(11, (i) => 67 + i));
    expect(surahsOfJuz(30).map((s) => s.number), List.generate(37, (i) => 78 + i));
  });
}
