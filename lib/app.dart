import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/app_config.dart';
import 'core/app_variant.dart';
import 'data/catalog/locations.dart';
import 'services/family/children_controller.dart';
import 'services/family/family_repository.dart';
import 'core/platform.dart';
import 'core/theme/app_theme.dart';
import 'features/prayer/prayer_calculator.dart';
import 'features/shell/sound_coordinator.dart';
import 'features/schedule/schedule_controller.dart';
import 'features/settings/settings_controller.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';
import 'services/app_lock/app_lock_service.dart';
import 'services/app_lock/protection_monitor.dart';
import 'services/audio/sfx_service.dart';
import 'services/notifications/prayer_notification_service.dart';
import 'variant/kids_localizations.dart';

class ZadXApp extends ConsumerStatefulWidget {
  const ZadXApp({super.key});

  @override
  ConsumerState<ZadXApp> createState() => _ZadXAppState();
}

class _ZadXAppState extends ConsumerState<ZadXApp> {
  late final RouteChangeSound _routeSound;

  @override
  void initState() {
    super.initState();
    _routeSound = RouteChangeSound(appRouter, () => ref.read(sfxProvider).play(Sfx.transition))..attach();
    // Reschedule adhan notifications whenever location/method changes,
    // and once at start-up (fireImmediately is only available on listenManual).
    // Zad X Kids has no adhan notifications.
    ref.listenManual<AppSettings>(
      settingsProvider,
      (prev, next) {
        if (kIsKids) {
          _syncKidsSettings(ref, next);
          return;
        }
        if (prev == null ||
            prev.cityId != next.cityId ||
            prev.methodId != next.methodId ||
            prev.asrFactor != next.asrFactor ||
            prev.highLatitude != next.highLatitude ||
            prev.language != next.language) {
          _reschedule(ref, next);
        }
        _syncSettings(ref, next);
      },
      fireImmediately: true,
    );
    if (kIsKids) {
      ref.listenManual<List<ScheduledLock>>(scheduleProvider, (_, __) => _syncKidsSettings(ref, ref.read(settingsProvider)));
    }
  }

  @override
  void dispose() {
    _routeSound.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    // Keeps native lock policy in sync with the wallet for the app's lifetime.
    ref.watch(lockCoordinatorProvider);
    // Tamper alert: reports protection state on start/resume (docs/decisions/DEVICE-PROTECTION.md).
    ref.watch(protectionMonitorProvider);
    // Star / task / unlock sounds.
    ref.watch(soundCoordinatorProvider);

    return MaterialApp.router(
      title: AppConfig.storeName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(settings.locale),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        // Zad X Kids: the same strings with every religious text replaced (variant/kids_strings.dart).
        kIsKids ? KidsLocalizationsDelegate() : AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: appRouter,
    );
  }

  /// Shares what other devices need (Windows Guard computes prayer locks from this).
  /// Parent devices only (R-33): family settings are parent-only in firestore.rules, and a paired
  /// child device must never overwrite the parent's adhan lock, games or lock mode.
  void _syncSettings(WidgetRef ref, AppSettings s) {
    if (ref.read(childrenProvider).isBound) return;
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
      // Effective high-latitude rule ('none' or a HighLatitudeRule name) for Windows Guard.
      'highLatRule': resolveHighLatitudeRule(s.highLatitude, city.lat)?.name ?? 'none',
      'lockAtAdhan': s.lockAtAdhan,
      'notifyOnTasks': s.notifyParentOnTasks,
      'notifyOnAdhan': s.notifyParentOnAdhan,
      'games': s.controlledGameIds.toList()..sort(),
      // Windows Guard scope (docs/decisions/DEVICE-WIDE-LOCK.md). The Android allow-list stays on the device.
      'lockMode': s.lockMode.name,
      'pcAllowBrowsers': s.pcAllowBrowsers,
    }).catchError((Object e) => debugPrint('settings sync failed: $e'));
  }

  /// Zad X Kids: what other devices need, without any prayer data (no city, method or adhan).
  /// Parent devices only, as [_syncSettings] (R-33): a paired child device never writes them.
  void _syncKidsSettings(WidgetRef ref, AppSettings s) {
    if (ref.read(childrenProvider).isBound) return;
    ref.read(familyRepositoryProvider).saveSettings({
      'variant': AppVariant.kids.name,
      'language': s.language,
      'lockAtAdhan': false,
      'notifyOnTasks': s.notifyParentOnTasks,
      'notifyOnAdhan': false,
      'games': s.controlledGameIds.toList()..sort(),
      'lockMode': s.lockMode.name,
      'pcAllowBrowsers': s.pcAllowBrowsers,
      'schedules': [for (final x in ref.read(scheduleProvider)) x.toJson()],
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
