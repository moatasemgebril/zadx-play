import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/models/plan.dart';

void main() {
  group('Feature matrix', () {
    test('Free has exactly app lock, prayer times, adhan and Quran', () {
      expect(featuresOf(null), {AppFeature.appLock, AppFeature.prayerTimes, AppFeature.adhan, AppFeature.quran});
    });

    test('Free ⊂ Basic ⊂ Plus, and Plus has every feature', () {
      expect(basicFeatures.containsAll(freeFeatures), isTrue);
      expect(plusFeatures.containsAll(basicFeatures), isTrue);
      expect(plusFeatures.length, greaterThan(basicFeatures.length));
      expect(plusFeatures, AppFeature.values.toSet());
    });

    test('Basic gets the core paid features, Plus keeps its extras', () {
      for (final f in [
        AppFeature.tasksRewards,
        AppFeature.games,
        AppFeature.eduGames,
        AppFeature.exercises,
        AppFeature.adhkar,
        AppFeature.customUnlockTasks,
        AppFeature.multipleChildren,
        AppFeature.assistant,
      ]) {
        expect(basicFeatures, contains(f), reason: f.name);
        expect(freeFeatures, isNot(contains(f)), reason: f.name);
      }
      for (final f in [AppFeature.consoleLinks, AppFeature.unlimitedAssistant, AppFeature.weeklyReport]) {
        expect(basicFeatures, isNot(contains(f)), reason: f.name);
      }
    });

    test('a trial is Plus', () {
      const trial = Entitlement(tier: PlanTier.plus, inTrial: true);
      for (final f in AppFeature.values) {
        expect(hasFeature(trial, f), isTrue, reason: f.name);
      }
      expect(trial.limits, same(planPlus));
    });

    test('free features never depend on login or purchase', () {
      final expired = Entitlement(
        tier: PlanTier.plus,
        expiresAt: DateTime.utc(2026, 1, 1),
        now: () => DateTime.utc(2026, 6, 1),
      );
      for (final ent in [const Entitlement(), expired]) {
        for (final f in freeFeatures) {
          expect(hasFeature(ent, f), isTrue, reason: f.name);
        }
        expect(hasFeature(ent, AppFeature.games), isFalse);
      }
    });
  });

  group('Limits', () {
    test('free users get the Free plan, not Basic', () {
      expect(const Entitlement().limits, same(planFree));
      expect(planFree.maxChildren, 1);
      expect(planFree.isFree, isTrue);
      expect(planFree.yearlySavingPercent, 0);
    });

    test('an expired paid plan falls back to Free', () {
      final ent = Entitlement(
        tier: PlanTier.basic,
        expiresAt: DateTime.utc(2026, 1, 1),
        now: () => DateTime.utc(2026, 2, 1),
      );
      expect(ent.effectiveTier, isNull);
      expect(ent.limits, same(planFree));
    });

    test('Basic and Plus keep their limits', () {
      expect(const Entitlement(tier: PlanTier.basic).limits, same(planBasic));
      expect(const Entitlement(tier: PlanTier.plus).limits, same(planPlus));
      expect(planBasic.maxChildren, 2);
      expect(planPlus.maxChildren, 5);
    });

    test('offers are shown Free, Basic, Plus', () {
      expect(allPlans.map((p) => p.tier), [null, PlanTier.basic, PlanTier.plus]);
    });
  });

  test('server tier strings: unknown is Free, never Basic', () {
    expect(parsePlanTier('basic'), PlanTier.basic);
    expect(parsePlanTier('plus'), PlanTier.plus);
    expect(parsePlanTier(null), isNull);
    expect(parsePlanTier(''), isNull);
    expect(parsePlanTier('gold'), isNull);
  });

  test('backend PLAN_FEATURES matches the app matrix', () {
    final src = File('backend/functions/src/security.ts').readAsStringSync();
    Set<String> list(String name) {
      final m = RegExp('$name: \\[([^\\]]*)\\]').firstMatch(src);
      expect(m, isNotNull, reason: 'PLAN_FEATURES.$name not found');
      return RegExp('"(\\w+)"').allMatches(m!.group(1)!).map((x) => x.group(1)!).toSet();
    }

    Set<String> names(Set<AppFeature> s) => s.map((f) => f.name).toSet();
    expect(list('free'), names(freeFeatures));
    expect(list('basic'), names(basicFeatures));
    expect(list('plus'), names(plusFeatures));
  });
}
