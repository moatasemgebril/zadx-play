import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time switches for features that must stay off until reviewed.
///
/// Every flag is OFF by default. A flag can only be turned on in a debug build,
/// and only explicitly, e.g.
/// `flutter run --dart-define=ZADX_LOCATION_MAP=true`.
/// Release and profile builds always get `false`, whatever is passed.
class FeatureFlags {
  const FeatureFlags({
    bool isDebugBuild = kDebugMode,
    bool locationMapRequested = _locationMapDefine,
  })  : _isDebugBuild = isDebugBuild,
        _locationMapRequested = locationMapRequested;

  static const _locationMapDefine = bool.fromEnvironment('ZADX_LOCATION_MAP');

  final bool _isDebugBuild;
  final bool _locationMapRequested;

  /// Parent-only child location map (docs/LOCATION_PRIVACY.md).
  /// Stays off in release until the policy, privacy-lawyer and owner reviews
  /// listed in that document are signed off.
  bool get locationMap => _isDebugBuild && !kReleaseMode && _locationMapRequested;
}

final featureFlagsProvider = Provider<FeatureFlags>((_) => const FeatureFlags());
