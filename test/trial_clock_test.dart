import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/core/app_config.dart';
import 'package:zadx/data/models/plan.dart';
import 'package:zadx/services/billing/trial_clock.dart';

/// 7-day Plus trial from the first launch (owner decision 2026-11-21, replaces R-16).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final start = DateTime.utc(2026, 11, 21, 9);

  test('the trial is 7 days', () {
    expect(AppConfig.trialDays, 7);
    expect(TrialClock.length, const Duration(days: 7));
  });

  group('TrialClock.resolve (pure)', () {
    test('first day: active with 7 days left', () {
      final s = TrialClock.resolve(startedAt: start, now: start);
      expect(s.active, isTrue);
      expect(s.daysLeft, 7);
      expect(s.endsAt, start.add(const Duration(days: 7)));
    });

    test('last hour: still active, 1 day left', () {
      final s = TrialClock.resolve(startedAt: start, now: start.add(const Duration(days: 6, hours: 23)));
      expect(s.active, isTrue);
      expect(s.daysLeft, 1);
    });

    test('exactly 7 days: ended', () {
      final s = TrialClock.resolve(startedAt: start, now: start.add(const Duration(days: 7)));
      expect(s.active, isFalse);
      expect(s.daysLeft, 0);
    });

    test('clock turned back after the end was seen does not reopen the trial', () {
      final s = TrialClock.resolve(
        startedAt: start,
        now: start.add(const Duration(days: 1)),
        highWater: start.add(const Duration(days: 8)),
      );
      expect(s.active, isFalse);
    });

    test('clock before the start counts as no time used, never more than 7 days', () {
      final s = TrialClock.resolve(startedAt: start, now: start.subtract(const Duration(days: 30)));
      expect(s.active, isTrue);
      expect(s.daysLeft, 7);
    });
  });

  group('TrialClock (stored on device)', () {
    test('starts on first launch and keeps the original start', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = start;
      final clock = TrialClock(prefs, clock: () => now);
      expect(clock.status().daysLeft, 7);
      now = start.add(const Duration(days: 3, hours: 1));
      // A new instance (app restart) reads the same start.
      expect(TrialClock(prefs, clock: () => now).status().daysLeft, 4);
    });

    test('ends after 7 days and stays ended when the clock is turned back', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = start;
      final clock = TrialClock(prefs, clock: () => now);
      clock.status();
      now = start.add(const Duration(days: 7, minutes: 1));
      expect(clock.status().active, isFalse);
      now = start.add(const Duration(days: 2)); // child turns the clock back
      expect(TrialClock(prefs, clock: () => now).status().active, isFalse);
    });

    test('turning the clock back mid-trial does not add days', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = start;
      final clock = TrialClock(prefs, clock: () => now);
      clock.status();
      now = start.add(const Duration(days: 5));
      expect(clock.status().daysLeft, 2);
      now = start.add(const Duration(days: 1));
      expect(clock.status().daysLeft, 2);
    });
  });

  group('resolveEntitlement', () {
    final active = TrialClock.resolve(startedAt: start, now: start.add(const Duration(days: 2)));
    final ended = TrialClock.resolve(startedAt: start, now: start.add(const Duration(days: 8)));

    test('during the trial: Plus with the days left, every feature open', () {
      final e = resolveEntitlement(trial: active);
      expect(e.isPlus, isTrue);
      expect(e.inTrial, isTrue);
      expect(e.trialDaysLeft, 5);
      for (final f in AppFeature.values) {
        expect(hasFeature(e, f), isTrue, reason: f.name);
      }
    });

    test('after 7 days with no purchase: Free (the trial never runs forever)', () {
      final e = resolveEntitlement(trial: ended);
      expect(e.isFree, isTrue);
      expect(e.inTrial, isFalse);
      expect(e.trialDaysLeft, isNull);
      expect(hasFeature(e, AppFeature.tasksRewards), isFalse);
      expect(hasFeature(e, AppFeature.adhkar), isTrue);
      expect(hasFeature(e, AppFeature.appLock), isTrue);
    });

    test('a verified purchase wins over the trial, and a cached tier keeps it offline', () {
      const paid = Entitlement(tier: PlanTier.basic);
      expect(resolveEntitlement(store: paid, trial: active), same(paid));
      expect(resolveEntitlement(cachedTier: PlanTier.basic, trial: ended).effectiveTier, PlanTier.basic);
      expect(resolveEntitlement(cachedTier: PlanTier.basic, trial: active).inTrial, isFalse);
    });

    test('a store answer of Free falls back to the trial, then Free', () {
      const free = Entitlement();
      expect(resolveEntitlement(store: free, trial: active).inTrial, isTrue);
      expect(resolveEntitlement(store: free, trial: ended).isFree, isTrue);
    });
  });
}
