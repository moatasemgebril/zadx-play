import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/catalog/locations.dart';
import '../../features/prayer/city_time_zone.dart';
import '../../features/prayer/prayer_calculator.dart';
import '../../features/prayer/prayer_schedule.dart';
import '../../features/settings/settings_controller.dart';

/// Schedules adhan notifications for today and tomorrow.
///
/// Sounds (add licensed files):
/// * Android: android/app/src/main/res/raw/adhan_short.mp3
/// * iOS:     ios/Runner/adhan_short.caf  (iOS notification sounds must be < 30 s)
class PrayerNotificationService {
  PrayerNotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'adhan_channel_v1';
  static const _silentChannelId = 'prayer_silent_v1';

  static const _adhanDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Adhan',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('adhan_short'),
      playSound: true,
    ),
    iOS: DarwinNotificationDetails(sound: 'adhan_short.caf', presentSound: true),
  );

  static const _silentDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _silentChannelId,
      'Prayer reminder (silent)',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
    ),
    iOS: DarwinNotificationDetails(presentSound: false),
  );

  Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestSoundPermission: true,
      requestBadgePermission: false,
    );
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> scheduleFor(AppSettings s, {required String Function(Prayer) prayerName, required String title}) async {
    await _plugin.cancelAll();
    final city = cityById(s.cityId);
    // DST-safe plan (see planAdhanNotifications): the old "midnight + hours" and
    // "now + 24 h" arithmetic put every adhan one hour off on clock-change days.
    final slots = planAdhanNotifications(
      now: tz.TZDateTime.now(cityLocation(city)),
      lat: city.lat,
      lng: city.lng,
      method: methodById(s.methodId),
      asrFactor: s.asrFactor,
      highLatitudeRule: resolveHighLatitudeRule(s.highLatitude, city.lat),
    );
    for (final slot in slots) {
      await _plugin.zonedSchedule(
        slot.id,
        title,
        prayerName(slot.prayer),
        slot.when,
        // A silent Isha reminder (Isha at/after the next Fajr): no adhan sound.
        slot.sound ? _adhanDetails : _silentDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }
}

final prayerNotificationServiceProvider =
    Provider<PrayerNotificationService>((_) => PrayerNotificationService(FlutterLocalNotificationsPlugin()));
