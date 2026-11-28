import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/core/feature_flags.dart';
import 'package:zadx/core/server_functions.dart';

void main() {
  test('location map is off by default', () {
    expect(const FeatureFlags().locationMap, isFalse);
  });

  test('location map is off by default in a debug build', () {
    expect(const FeatureFlags(isDebugBuild: true).locationMap, isFalse);
  });

  test('location map can be enabled explicitly in a debug build', () {
    const flags = FeatureFlags(isDebugBuild: true, locationMapRequested: true);
    expect(flags.locationMap, isTrue);
  });

  test('location map stays off in a release/profile build even if requested', () {
    const flags = FeatureFlags(isDebugBuild: false, locationMapRequested: true);
    expect(flags.locationMap, isFalse);
  });

  test('tests run in debug mode, so the release guard is not what keeps it off here', () {
    expect(kReleaseMode, isFalse);
  });

  test('provider exposes the default (off) flags', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(featureFlagsProvider).locationMap, isFalse);
    expect(c.read(featureFlagsProvider).serverFunctions, isFalse);
  });

  group('zero-cost backend (owner decision 2026-11-28)', () {
    test('server functions, assistant and referral rewards are off by default', () {
      const flags = FeatureFlags();
      expect(flags.serverFunctions, isFalse);
      expect(flags.assistant, isFalse);
      expect(flags.referralRewards, isFalse);
      expect(appFeatureFlags.serverFunctions, isFalse);
    });

    test('the assistant and referrals never turn on without server functions', () {
      const flags = FeatureFlags(assistantRequested: true, referralsRequested: true);
      expect(flags.assistant, isFalse);
      expect(flags.referralRewards, isFalse);
    });

    test('server functions alone do not show the assistant or the referral card', () {
      const flags = FeatureFlags(serverFunctionsRequested: true);
      expect(flags.serverFunctions, isTrue);
      expect(flags.assistant, isFalse);
      expect(flags.referralRewards, isFalse);
    });

    test('a Blaze build can re-enable each one explicitly', () {
      const flags = FeatureFlags(serverFunctionsRequested: true, assistantRequested: true, referralsRequested: true);
      expect(flags.assistant, isTrue);
      expect(flags.referralRewards, isTrue);
    });

    test('default gateway makes no Cloud Functions call: it fails with ServerFunctionsDisabled', () async {
      final calls = serverCallsFor();
      expect(calls, isA<DisabledServerCalls>());
      expect(calls.enabled, isFalse);
      await expectLater(calls.call('verifyPurchase', {'productId': 'x'}), throwsA(isA<ServerFunctionsDisabled>()));
    });

    test('the gateway provider follows the flags', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(serverCallsProvider).enabled, isFalse);
      final blaze = ProviderContainer(overrides: [
        featureFlagsProvider.overrideWithValue(const FeatureFlags(serverFunctionsRequested: true)),
      ]);
      addTearDown(blaze.dispose);
      expect(blaze.read(serverCallsProvider), isA<FirebaseServerCalls>());
    });
  });
}
