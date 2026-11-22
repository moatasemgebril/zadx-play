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
import 'services/billing/subscription_service.dart';
import 'services/family/family_repository.dart';
import 'services/family/firestore_family_repository.dart';
import 'services/notifications/prayer_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  final prefs = await SharedPreferences.getInstance();

  // Firebase is optional during development: without google-services.json /
  // GoogleService-Info.plist the app runs in single-device (local) mode.
  var firebaseReady = false;
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (e) {
    debugPrint('Firebase not configured, running locally: $e');
  }

  String? familyId = prefs.getString('family.id');
  if (firebaseReady) {
    try {
      familyId = await FirestoreFamilyRepository.ensureFamily(familyId);
      await prefs.setString('family.id', familyId);
    } catch (e) {
      debugPrint('Family setup failed, staying local: $e');
      familyId = null;
    }
  }

  final container = ProviderContainer(overrides: [
    sharedPrefsProvider.overrideWithValue(prefs),
    firebaseReadyProvider.overrideWithValue(firebaseReady),
    familyIdProvider.overrideWith((_) => familyId),
  ]);

  // Adhan notifications: Zad X Play only (Zad X Kids has no prayer times).
  if (!kIsKids && AppPlatform.canScheduleNotifications) {
    await container.read(prayerNotificationServiceProvider).init();
  }
  if (firebaseReady && AppPlatform.canPurchase) {
    container.read(subscriptionServiceProvider).init().catchError((Object e) => debugPrint('IAP init: $e'));
  }

  runApp(UncontrolledProviderScope(container: container, child: const ZadXApp()));
}
