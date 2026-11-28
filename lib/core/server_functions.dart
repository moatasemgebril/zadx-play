import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';
import 'feature_flags.dart';

/// The single gateway to Cloud Functions for billing (`verifyPurchase`), the assistant
/// (`askAssistant`), referrals (`referralStatus`) and parent alerts (`notifyParent`,
/// `reportProtection`).
///
/// Owner decision 2026-11-28 (zero cost, Spark): [FeatureFlags.serverFunctions] is false, so
/// [serverCallsFor] returns [DisabledServerCalls], which never touches Firebase Functions. The
/// Firebase implementation is kept only so a Blaze build can turn the old paths back on.
abstract class ServerCalls {
  const ServerCalls();

  /// False when every [call] fails with [ServerFunctionsDisabled].
  bool get enabled;

  /// Calls the Cloud Function [name] and returns its `data` (a Map for every Zad X function).
  /// Throws [ServerCallException] when the function answers with an error.
  Future<Object?> call(String name, [Map<String, Object?>? data, Duration? timeout]);
}

/// A Cloud Function answered with an error (`code` as in FirebaseFunctionsException).
class ServerCallException implements Exception {
  const ServerCallException(this.code, [this.message]);
  final String code;
  final String? message;
  @override
  String toString() => 'ServerCallException($code)';
}

/// Thrown instead of calling a Cloud Function while [FeatureFlags.serverFunctions] is false.
class ServerFunctionsDisabled implements Exception {
  const ServerFunctionsDisabled(this.name);
  final String name;
  @override
  String toString() => 'ServerFunctionsDisabled($name)';
}

/// Spark (default): no Cloud Functions at all.
class DisabledServerCalls extends ServerCalls {
  const DisabledServerCalls();

  @override
  bool get enabled => false;

  @override
  Future<Object?> call(String name, [Map<String, Object?>? data, Duration? timeout]) =>
      Future<Object?>.error(ServerFunctionsDisabled(name));
}

/// Blaze only: the deployed functions in [functionsRegion].
class FirebaseServerCalls extends ServerCalls {
  FirebaseServerCalls([FirebaseFunctions? functions]) : _functions = functions;
  final FirebaseFunctions? _functions;

  @override
  bool get enabled => true;

  @override
  Future<Object?> call(String name, [Map<String, Object?>? data, Duration? timeout]) async {
    final callable = (_functions ?? zadFunctions()).httpsCallable(
      name,
      // 60 s is the plugin's own default timeout.
      options: HttpsCallableOptions(timeout: timeout ?? const Duration(seconds: 60)),
    );
    try {
      final result = await callable.call(data);
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      throw ServerCallException(e.code, e.message);
    }
  }
}

/// The gateway for [flags] (this build's flags by default).
ServerCalls serverCallsFor([FeatureFlags flags = appFeatureFlags]) =>
    flags.serverFunctions ? FirebaseServerCalls() : const DisabledServerCalls();

final serverCallsProvider = Provider<ServerCalls>((ref) => serverCallsFor(ref.watch(featureFlagsProvider)));
