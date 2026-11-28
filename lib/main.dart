import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

import 'app.dart';
import 'core/app_variant.dart';
import 'core/platform.dart';
import 'features/settings/settings_controller.dart';
import 'features/splash/launch_splash.dart';
import 'services/billing/subscription_service.dart';
import 'services/family/device_removal.dart';
import 'services/family/family_bootstrap.dart';
import 'services/family/family_repository.dart';
import 'services/family/firestore_family_repository.dart';
import 'services/notifications/prayer_notification_service.dart';

/// Network steps of start-up never hold the app longer than this (offline phones start locally).
const _networkStepTimeout = Duration(seconds: 5);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Brand splash first; the start-up work below runs while it plays (features/splash/). If it
  // throws, the splash shows a friendly "Try again" screen instead of staying up forever.
  final splash = LaunchSplash.show(retry: startUpApp);
  try {
    splash.complete(await startUpApp());
  } catch (e, st) {
    debugPrint('start-up failed: $e');
    splash.fail(e, st);
  }
}

/// Everything the app needs before its first screen. Safe to run again (the "Try again" button).
/// Optional services (Firebase, family sync, notifications, purchases) fail soft: the app then
/// starts in local mode. Only a failure of local storage is fatal (the fallback screen).
Future<Widget> startUpApp() async {
  tzdata.initializeTimeZones();

  final prefs = await SharedPreferences.getInstance();

  // Firebase is optional during development: without google-services.json /
  // GoogleService-Info.plist the app runs in single-device (local) mode.
  var firebaseReady = false;
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp().timeout(_networkStepTimeout);
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase not configured, running locally: $e');
  }

  // Removed from the family (P1-3a): the old family's Firestore cache goes first (only possible
  // before Firestore is used), and no new family is made until a parent sets the device up again.
  final removed = prefs.getBool(DeviceRemoval.removedKey) ?? false;
  if (removed) await DeviceRemoval.clearFamilyData(prefs); // idempotent: finishes an interrupted reset
  if (firebaseReady) await DeviceRemoval.clearFirestoreCacheIfPending(prefs, timeout: _networkStepTimeout);

  String? familyId = removed ? null : prefs.getString(FamilyBootstrap.idKey);
  if (firebaseReady && !removed) {
    // The id is saved locally before the family doc is written (no orphan family on a timeout).
    familyId = await FamilyBootstrap.run(
      prefs,
      newId: FirestoreFamilyRepository.newFamilyId,
      signIn: FirestoreFamilyRepository.signIn,
      create: FirestoreFamilyRepository.createFamily,
      timeout: _networkStepTimeout,
    );
  }

  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    firebaseReadyProvider.overrideWithValue(firebaseReady),
    familyIdProvider.overrideWith((_) => familyId),
  ]);

  // Adhan notifications: Zad X Play only (Zad X Kids has no prayer times). Not fatal.
  if (!kIsKids && AppPlatform.canScheduleNotifications) {
    try {
      await container.read(prayerNotificationServiceProvider).init().timeout(_networkStepTimeout);
    } catch (e) {
      debugPrint('Notifications init failed: $e');
    }
  }
  if (firebaseReady && AppPlatform.canPurchase) {
    container.read(subscriptionServiceProvider).init().catchError((Object e) => debugPrint('IAP init: $e'));
  }

  return UncontrolledProviderScope(container: container, child: const ZadXApp());
}
