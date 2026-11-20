import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../data/catalog/locations.dart';
import '../../features/prayer/prayer_calculator.dart';
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
    final location = tz.getLocation(city.timeZone);
    final calc = const PrayerCalculator();

    for (var dayOffset = 0; dayOffset < 2; dayOffset++) {
      final base = tz.TZDateTime.now(location).add(Duration(days: dayOffset));
      final times = calc.compute(
        date: base,
        lat: city.lat,
        lng: city.lng,
        utcOffsetHours: base.timeZoneOffset.inMinutes / 60,
        method: methodById(s.methodId),
        asrFactor: s.asrFactor,
      );
      for (final p in Prayer.values) {
        final h = times.of(p);
        if (!h.isFinite) continue;
        final when = tz.TZDateTime(location, base.year, base.month, base.day).add(Duration(minutes: (h * 60).round()));
        if (when.isBefore(tz.TZDateTime.now(location))) continue;
        await _plugin.zonedSchedule(
          dayOffset * 10 + p.index,
          title,
          prayerName(p),
          when,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              'Adhan',
              importance: Importance.max,
              priority: Priority.high,
              sound: RawResourceAndroidNotificationSound('adhan_short'),
              playSound: true,
            ),
            iOS: DarwinNotificationDetails(sound: 'adhan_short.caf', presentSound: true),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }
}

final prayerNotificationServiceProvider =
    Provider<PrayerNotificationService>((_) => PrayerNotificationService(FlutterLocalNotificationsPlugin()));
