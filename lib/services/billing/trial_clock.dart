import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_config.dart';
import '../../data/models/plan.dart';
import '../../features/settings/settings_controller.dart';
import 'entitlement_cache.dart' show Clock;

/// The on-device Plus trial at one moment.
@immutable
class TrialStatus {
  const TrialStatus({required this.startedAt, required this.endsAt, required this.active, required this.daysLeft});

  /// First launch (UTC).
  final DateTime startedAt;

  /// [startedAt] + [TrialClock.length].
  final DateTime endsAt;
  final bool active;

  /// Whole days left, rounded up (7 on the first day, 1 on the last); 0 once ended.
  final int daysLeft;
}

/// 7-day Plus trial from the first launch (owner decision 2026-11-21, replaces the
/// never-ending client trial, risk R-16). After it ends with no purchase the family is Free.
///
/// Tamper resistance, same model as [EntitlementCache]:
/// * The first-launch time is written once and never moved.
/// * A trial-specific high-water mark remembers the latest time ever seen. Elapsed time is
///   measured to `max(now, highWater)`, so turning the device clock back never gives more
///   trial than what was already observed, and once the end was observed the trial stays
///   ended for good.
/// * Unlike the paid-plan cache, nothing resets this high-water mark (a purchase does not
///   need it, and a reset would let a clock trick re-open the trial).
/// * Moving the clock forward only ends the trial early (never a safety issue).
/// * Residual (accepted): clearing the app's data or reinstalling starts a new trial. That
///   also erases the parent PIN and settings, which a parent notices. A server-side trial per
///   family would close this (BACKLOG "Offline-first"). The trial only adds paid features; it
///   never lifts a lock, so this cannot weaken child safety.
class TrialClock {
  TrialClock(this._prefs, {Clock? clock}) : _clock = clock ?? DateTime.now;

  static const length = Duration(days: AppConfig.trialDays);

  static const _kStartedAt = 'billing.trial.startedAtMs';
  static const _kHighWater = 'billing.trial.highWaterMs';

  final SharedPreferences _prefs;
  final Clock _clock;

  /// Pure decision (unit-tested).
  static TrialStatus resolve({required DateTime startedAt, required DateTime now, DateTime? highWater}) {
    final start = startedAt.toUtc();
    final nowUtc = now.toUtc();
    final reference = (highWater != null && highWater.isAfter(nowUtc)) ? highWater.toUtc() : nowUtc;
    var elapsed = reference.difference(start);
    if (elapsed.isNegative) elapsed = Duration.zero;
    final left = length - elapsed;
    final active = left > Duration.zero;
    const day = Duration(days: 1);
    final daysLeft = active ? ((left.inMicroseconds + day.inMicroseconds - 1) ~/ day.inMicroseconds) : 0;
    return TrialStatus(startedAt: start, endsAt: start.add(length), active: active, daysLeft: daysLeft);
  }

  DateTime? _read(String key) {
    final ms = _prefs.getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  /// Trial status now. Starts the trial on the first call and advances the high-water mark.
  TrialStatus status() {
    final now = _clock().toUtc();
    var started = _read(_kStartedAt);
    if (started == null) {
      started = now;
      unawaited(_prefs.setInt(_kStartedAt, now.millisecondsSinceEpoch));
    }
    final previous = _read(_kHighWater);
    var highWater = (previous == null || now.isAfter(previous)) ? now : previous;
    // The high-water mark is never earlier than the start.
    if (highWater.isBefore(started)) highWater = started;
    if (highWater != previous) {
      unawaited(_prefs.setInt(_kHighWater, highWater.millisecondsSinceEpoch));
    }
    return resolve(startedAt: started, now: now, highWater: highWater);
  }
}

final trialClockProvider = Provider<TrialClock>((ref) => TrialClock(ref.watch(sharedPrefsProvider)));

/// What the family has right now (pure, unit-tested). In order:
/// 1. the highest active paid plan the server confirmed: this device's own store purchase
///    (`verifyPurchase`) or the family doc's plan (bought on another family phone),
/// 2. the last verified paid tier still inside its offline grace ([EntitlementCache]),
/// 3. the on-device Plus trial,
/// 4. Free.
Entitlement resolveEntitlement({Entitlement? store, Entitlement? family, PlanTier? cachedTier, required TrialStatus trial}) {
  final paid = bestVerifiedEntitlement(store, family);
  if (paid != null && !paid.isFree) return paid;
  if (cachedTier != null) return Entitlement(tier: cachedTier);
  if (trial.active) return Entitlement(tier: PlanTier.plus, inTrial: true, trialDaysLeft: trial.daysLeft, deviceTrial: true);
  return const Entitlement();
}

int _rank(PlanTier? tier) => switch (tier) { PlanTier.plus => 2, PlanTier.basic => 1, null => 0 };

/// The better of two server-confirmed answers (highest tier still active now). `null` only when
/// neither source has answered yet; an answer of Free (e.g. expired) is kept, so it can clear
/// the offline cache.
Entitlement? bestVerifiedEntitlement(Entitlement? a, Entitlement? b) {
  if (a == null) return b;
  if (b == null) return a;
  return _rank(b.effectiveTier) > _rank(a.effectiveTier) ? b : a;
}
