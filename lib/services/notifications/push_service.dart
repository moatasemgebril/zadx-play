import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform.dart';
import '../../features/settings/settings_controller.dart';
import '../../router.dart';
import '../family/children_controller.dart';
import '../family/family_repository.dart';
import 'push_payload.dart';

/// unavailable: no Firebase config (CI / dev), not a phone, or a paired child device.
enum PushStatus { unavailable, off, on, denied }

enum PushEnableResult { enabled, denied, failed }

/// Parent-only server push (docs/PUSH_NOTIFICATIONS.md).
///
/// OFF by default; the parent opts in from the parent area. When on, this device's FCM token
/// is stored at `families/{familyId}/parentDevices/{uid}` = {token, platform, lang, updatedAt}
/// (see backend/firestore.rules). Nothing here touches Firebase Messaging unless Firebase is
/// configured, so the app still starts without google-services files.
class PushController extends Notifier<PushStatus> {
  static const optInKey = 'push.optIn';

  StreamSubscription<String>? _tokenSub;

  bool get _available => canUseParentPush(
        firebaseReady: ref.read(firebaseReadyProvider),
        isMobile: AppPlatform.isAndroid || AppPlatform.isIOS,
        isBoundChildDevice: ref.read(childrenProvider).isBound,
        hasFamily: ref.read(familyIdProvider) != null,
      );

  @override
  PushStatus build() {
    // Rebuild when the device is paired to another family or bound to a child.
    ref.watch(familyIdProvider);
    ref.watch(childrenProvider.select((s) => s.isBound));
    ref.onDispose(() {
      _tokenSub?.cancel();
      _tokenSub = null;
    });
    if (!_available) return PushStatus.unavailable;

    // Keep the stored language in sync so the server sends AR or EN copy.
    ref.listen<String>(settingsProvider.select((s) => s.language), (prev, next) {
      if (prev != next && state == PushStatus.on) unawaited(_register());
    });

    final optedIn = ref.read(sharedPrefsProvider).getBool(optInKey) ?? false;
    if (!optedIn) return PushStatus.off;
    // Refresh the token after start-up (tokens rotate), without blocking the first frame.
    Future.microtask(_register);
    return PushStatus.on;
  }

  /// Shows the OS permission prompt, then registers this device. Call after the in-app
  /// explanation dialog (see PushSettingsCard).
  Future<PushEnableResult> enable() async {
    if (!_available) return PushEnableResult.failed;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(alert: true, badge: false, sound: true);
      final granted = settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!granted) {
        state = PushStatus.denied;
        return PushEnableResult.denied;
      }
      final ok = await _register();
      if (!ok) return PushEnableResult.failed;
      await ref.read(sharedPrefsProvider).setBool(optInKey, true);
      state = PushStatus.on;
      return PushEnableResult.enabled;
    } catch (e) {
      debugPrint('push enable failed: $e');
      return PushEnableResult.failed;
    }
  }

  /// Opt-out: deletes the token doc and the token itself (data minimisation).
  Future<void> disable() async {
    await ref.read(sharedPrefsProvider).setBool(optInKey, false);
    await _tokenSub?.cancel();
    _tokenSub = null;
    if (_available) {
      state = PushStatus.off;
      try {
        await _deviceDoc()?.delete();
        await FirebaseMessaging.instance.deleteToken();
      } catch (e) {
        debugPrint('push disable cleanup failed: $e');
      }
    }
  }

  DocumentReference<Map<String, dynamic>>? _deviceDoc() {
    final familyId = ref.read(familyIdProvider);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (familyId == null || uid == null) return null;
    return FirebaseFirestore.instance.doc('families/$familyId/parentDevices/$uid');
  }

  /// Writes the current token; returns false when there is no token yet (e.g. iOS before
  /// the APNs key is uploaded) or the write was refused.
  Future<bool> _register() async {
    if (!_available) return false;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return false;
      await _write(token);
      _tokenSub ??= FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        _write(t).catchError((Object e) => debugPrint('push token refresh failed: $e'));
      });
      return true;
    } catch (e) {
      debugPrint('push register failed: $e');
      return false;
    }
  }

  Future<void> _write(String token) async {
    final doc = _deviceDoc();
    if (doc == null) return;
    await doc.set({
      'token': token,
      'platform': AppPlatform.isIOS ? 'ios' : 'android',
      'lang': pushLangFor(ref.read(settingsProvider).language),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

final pushControllerProvider = NotifierProvider<PushController, PushStatus>(PushController.new);

/// Opening a parent push goes to the PIN-protected parent area, which loads the details.
/// Call once from main() when Firebase is ready on a phone.
Future<void> initPushTapHandling() async {
  void open(RemoteMessage m) {
    if (ParentPush.fromData(m.data) != null) appRouter.go(Routes.parent);
  }

  try {
    FirebaseMessaging.onMessageOpenedApp.listen(open);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) open(initial);
  } catch (e) {
    debugPrint('push tap handling unavailable: $e');
  }
}
