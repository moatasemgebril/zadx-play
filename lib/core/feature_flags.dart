import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time switches for features that must stay off until reviewed.
///
/// Every flag is OFF by default.
///
/// * [locationMap] can only be turned on in a debug build, and only explicitly, e.g.
///   `flutter run --dart-define=ZADX_LOCATION_MAP=true`. Release and profile builds always get
///   `false`, whatever is passed.
/// * [serverFunctions] is the backend switch (owner decision 2026-11-28: zero cost, Firebase
///   Spark, no Cloud Functions). While it is false the app never calls a Cloud Function for
///   billing, the assistant, referrals or parent alerts: purchases are trusted on the device that
///   bought them, alerts are Firestore event docs. If the owner ever chooses Blaze, a build with
///   `--dart-define=ZADX_SERVER_FUNCTIONS=true` re-enables the old server paths.
/// * [assistant] and [referralRewards] need [serverFunctions] AND their own define
///   (`ZADX_ASSISTANT`, `ZADX_REFERRALS`): the assistant needs an AI key that may only live on a
///   server, and referral rewards need server-side counting. Off in every build today.
class FeatureFlags {
  const FeatureFlags({
    bool isDebugBuild = kDebugMode,
    bool locationMapRequested = _locationMapDefine,
    bool serverFunctionsRequested = _serverFunctionsDefine,
    bool assistantRequested = _assistantDefine,
    bool referralsRequested = _referralsDefine,
  })  : _isDebugBuild = isDebugBuild,
        _locationMapRequested = locationMapRequested,
        _serverFunctionsRequested = serverFunctionsRequested,
        _assistantRequested = assistantRequested,
        _referralsRequested = referralsRequested;

  static const _locationMapDefine = bool.fromEnvironment('ZADX_LOCATION_MAP');
  static const _serverFunctionsDefine = bool.fromEnvironment('ZADX_SERVER_FUNCTIONS');
  static const _assistantDefine = bool.fromEnvironment('ZADX_ASSISTANT');
  static const _referralsDefine = bool.fromEnvironment('ZADX_REFERRALS');

  final bool _isDebugBuild;
  final bool _locationMapRequested;
  final bool _serverFunctionsRequested;
  final bool _assistantRequested;
  final bool _referralsRequested;

  /// Parent-only child location map (docs/LOCATION_PRIVACY.md).
  /// Stays off in release until the policy, privacy-lawyer and owner reviews
  /// listed in that document are signed off.
  bool get locationMap => _isDebugBuild && !kReleaseMode && _locationMapRequested;

  /// Cloud Functions (Blaze plan) are available. False on the free Spark plan (default).
  bool get serverFunctions => _serverFunctionsRequested;

  /// The parent AI assistant (Help screen, plan feature lists). Hidden unless the server holds
  /// the AI key: the app must never contain one.
  bool get assistant => serverFunctions && _assistantRequested;

  /// The invite-a-friend reward card on the plans screen. Hidden until a free design exists.
  bool get referralRewards => serverFunctions && _referralsRequested;
}

/// The flags of this build (all off unless a `--dart-define` turns one on).
const appFeatureFlags = FeatureFlags();

final featureFlagsProvider = Provider<FeatureFlags>((_) => appFeatureFlags);
