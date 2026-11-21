import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/core/feature_flags.dart';

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
  });
}
