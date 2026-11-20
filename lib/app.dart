import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_config.dart';
import 'data/catalog/locations.dart';
import 'services/family/family_repository.dart';
import 'core/platform.dart';
import 'core/theme/app_theme.dart';
import 'features/prayer/prayer_calculator.dart';
import 'features/settings/settings_controller.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'services/app_lock/app_lock_service.dart';
import 'services/notifications/prayer_notification_service.dart';

class ZadXApp extends ConsumerWidget {
  const ZadXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    // Keeps native lock policy in sync with the wallet for the app's lifetime.
    ref.watch(lockCoordinatorProvider);

    // Reschedule adhan notifications whenever location/method changes.
    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if (prev == null ||
          prev.cityId != next.cityId ||
          prev.methodId != next.methodId ||
          prev.asrFactor != next.asrFactor ||
          prev.language != next.language) {
        _reschedule(ref, next);
      }
      _syncSettings(ref, next);
    }, fireImmediately: true);

    return MaterialApp.router(
      title: AppConfig.storeName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.locale),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
    );
  }

  /// Shares what other devices need (Windows Guard computes prayer locks from this).
  void _syncSettings(WidgetRef ref, AppSettings s) {
    final city = cityById(s.cityId);
    final method = methodById(s.methodId);
    ref.read(familyRepositoryProvider).saveSettings({
      'language': s.language,
      'cityId': city.id,
      'lat': city.lat,
      'lng': city.lng,
      'timeZone': city.timeZone,
      'fajrAngle': method.fajrAngle,
      'ishaAngle': method.ishaAngle,
      'ishaMinutes': method.ishaMinutesAfterMaghrib,
      'asrFactor': s.asrFactor,
      'lockAtAdhan': s.lockAtAdhan,
      'notifyOnTasks': s.notifyParentOnTasks,
      'notifyOnAdhan': s.notifyParentOnAdhan,
      'games': s.controlledGameIds.toList()..sort(),
    }).catchError((Object e) => debugPrint('settings sync failed: $e'));
  }

  Future<void> _reschedule(WidgetRef ref, AppSettings s) async {
    if (!AppPlatform.canScheduleNotifications) return;
    final l10n = lookupAppLocalizations(s.locale);
    final names = {
      Prayer.fajr: l10n.fajr,
      Prayer.dhuhr: l10n.dhuhr,
      Prayer.asr: l10n.asr,
      Prayer.maghrib: l10n.maghrib,
      Prayer.isha: l10n.isha,
    };
    await ref.read(prayerNotificationServiceProvider).scheduleFor(
          s,
          prayerName: (p) => l10n.prayerNow(names[p]!),
          title: AppConfig.brandName,
        );
  }
}
