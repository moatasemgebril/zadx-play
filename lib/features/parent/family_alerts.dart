import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_variant.dart';
import '../../core/feature_flags.dart';
import '../../core/l10n_ext.dart';
import '../../core/platform.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_localizations.dart';
import '../../services/family/children_controller.dart';
import '../../services/family/family_events.dart';
import '../../services/family/family_repository.dart';
import '../../variant/kids_localizations.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../settings/settings_controller.dart';
import 'children_card.dart' show childDisplayName;

// Parent side of the zero-cost family alerts (owner decision 2026-11-28: no server, no push).
// The child devices write event docs and their presence (services/family/family_events.dart);
// this phone lists them in the parent area and, while Zad X is open or comes back to the
// foreground, shows a local notification for each new one. Notification texts never contain
// the child's name (they can appear on the lock screen); the PIN-protected list does.

/// Shows one local notification. Replaced by a fake in tests.
abstract class FamilyAlertSink {
  Future<void> show(int id, String title, String body);
}

/// flutter_local_notifications, initialised on first use (Zad X Kids has no adhan notifications,
/// so nothing else initialises the plugin there).
class LocalNotificationAlertSink implements FamilyAlertSink {
  LocalNotificationAlertSink([FlutterLocalNotificationsPlugin? plugin]) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'family_alerts_v1',
      'Family alerts',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _init() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestAlertPermission: true, requestSoundPermission: true, requestBadgePermission: false),
    );
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  @override
  Future<void> show(int id, String title, String body) async {
    if (!AppPlatform.canScheduleNotifications) return;
    await (_ready ??= _init());
    await _plugin.show(id, title, body, _details);
  }
}

final familyAlertSinkProvider = Provider<FamilyAlertSink>((_) => LocalNotificationAlertSink());

/// The newest event time this phone already notified (ms since epoch, server time).
const alertsNotifiedUntilKey = 'family.alerts.notifiedUntilMs';

/// Per child: the `lastSeen` (ms) a "not checking in" notification was already shown for.
String staleNotifiedKey(String childId) => 'family.alerts.staleNotified.$childId';

/// True on a parent device of a synced family (a paired child device never reads the alerts).
final isParentAlertDeviceProvider = Provider<bool>(
  (ref) => !ref.watch(childrenProvider.select((c) => c.isBound)),
);

/// Recent family events (parent devices only). Never emits in local mode.
final familyEventsProvider = StreamProvider<List<FamilyEvent>>((ref) {
  if (!ref.watch(isParentAlertDeviceProvider)) return const Stream<List<FamilyEvent>>.empty();
  return ref.watch(familyRepositoryProvider).watchEvents();
});

/// Last seen + protection state per child device (parent devices only).
final familyPresenceProvider = StreamProvider<Map<String, ChildPresence>>((ref) {
  if (!ref.watch(isParentAlertDeviceProvider)) return const Stream<Map<String, ChildPresence>>.empty();
  return ref.watch(familyRepositoryProvider).watchPresence();
});

/// The text of an event (no child name).
String familyEventText(FamilyEvent e, AppLocalizations l10n) => switch (e.type) {
      FamilyEventType.taskSubmitted => l10n.notifTaskSubmitted,
      FamilyEventType.adhan => l10n.notifAdhan,
      _ => l10n.notifProtection,
    };

/// "3:25 PM" today, "27/11 3:25 PM" on another day (device time zone, chosen digits).
String formatSeenTime(DateTime t, DateTime now, String lang) {
  final local = t.toLocal();
  final today = now.toLocal();
  final time = Fmt.hours(local.hour + local.minute / 60, lang);
  final sameDay = local.year == today.year && local.month == today.month && local.day == today.day;
  return sameDay ? time : '${Fmt.digits('${local.day}/${local.month}', lang)} $time';
}

AppLocalizations _l10nFor(Locale locale) => kIsKids ? kidsLocalizationsFor(locale) : lookupAppLocalizations(locale);

/// Parent phone: turns new events and silent child devices into local notifications while the
/// app runs (watched by ZadXApp). On Blaze the server pushes instead, so this stays off there.
final familyAlertsNotifierProvider = Provider<void>((ref) {
  if (ref.watch(featureFlagsProvider).serverFunctions) return;
  if (!ref.watch(isParentAlertDeviceProvider)) return;
  final prefs = ref.watch(sharedPrefsProvider);
  final sink = ref.watch(familyAlertSinkProvider);
  unawaited(ref.read(familyRepositoryProvider).pruneEvents().catchError((Object e) => debugPrint('prune: $e')));

  ref.listen<AsyncValue<List<FamilyEvent>>>(familyEventsProvider, (_, next) {
    final events = next.valueOrNull;
    if (events == null) return;
    final storedMs = prefs.getInt(alertsNotifiedUntilKey);
    if (storedMs == null) {
      // First run on this phone: start from now, never a flood of old alerts.
      unawaited(prefs.setInt(alertsNotifiedUntilKey, DateTime.now().toUtc().millisecondsSinceEpoch));
      return;
    }
    final fresh = eventsToNotify(events, DateTime.fromMillisecondsSinceEpoch(storedMs, isUtc: true));
    if (fresh.isEmpty) return;
    unawaited(prefs.setInt(alertsNotifiedUntilKey, fresh.last.at!.millisecondsSinceEpoch));
    final s = ref.read(settingsProvider);
    final l10n = _l10nFor(s.locale);
    final wanted = [
      for (final e in fresh)
        if (eventWanted(e, notifyOnTasks: s.notifyParentOnTasks, notifyOnAdhan: s.notifyParentOnAdhan, adhanSupported: !kIsKids)) e,
    ];
    // At most the 3 newest at once (e.g. after the phone was offline for a day).
    for (final e in wanted.reversed.take(3)) {
      unawaited(sink.show(_notificationId(e.id), l10n.familyAlertsTitle, familyEventText(e, l10n)).catchError((Object err) {
        debugPrint('alert notification failed: $err');
      }));
    }
  }, fireImmediately: true);

  ref.listen<AsyncValue<Map<String, ChildPresence>>>(familyPresenceProvider, (_, next) {
    final all = next.valueOrNull;
    if (all == null) return;
    final now = DateTime.now().toUtc();
    for (final p in all.values) {
      if (!p.isStale(now)) continue;
      final seenMs = p.lastSeen!.millisecondsSinceEpoch;
      if (prefs.getInt(staleNotifiedKey(p.childId)) == seenMs) continue;
      unawaited(prefs.setInt(staleNotifiedKey(p.childId), seenMs));
      final l10n = _l10nFor(ref.read(settingsProvider).locale);
      unawaited(sink.show(_notificationId('stale-${p.childId}'), l10n.familyAlertsTitle, l10n.notifStale).catchError((Object err) {
        debugPrint('alert notification failed: $err');
      }));
    }
  }, fireImmediately: true);
});

/// Notification ids 910000–919999: away from the adhan notification ids.
int _notificationId(String key) => 910000 + (key.hashCode & 0x7fffffff) % 10000;

/// Parent area: last seen per child device and the alerts of the last 7 days. Hidden for a
/// one-device (local) family and on child devices.
class FamilyAlertsCard extends ConsumerWidget {
  const FamilyAlertsCard({super.key, this.now});

  /// Clock override for tests.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(familyEventsProvider).valueOrNull;
    final presence = ref.watch(familyPresenceProvider).valueOrNull;
    if (events == null && presence == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final lang = context.lang;
    final children = ref.watch(childrenProvider);
    final t = (now ?? DateTime.now)().toUtc();
    // Zad X Kids has no prayer lock: an adhan event is never shown there.
    final recent = recentEvents(events ?? const [], t).where((e) => !kIsKids || e.type != FamilyEventType.adhan).take(10).toList();
    final kids = (presence ?? const <String, ChildPresence>{}).values.toList();
    String nameOf(String id) {
      final c = children.byId(id);
      return c == null ? l10n.childDefaultName : childDisplayName(c, l10n);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ZadCard(
        key: const Key('familyAlertsCard'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(l10n.familyAlertsTitle, style: Theme.of(context).textTheme.titleMedium),
          Text(l10n.familyAlertsNote, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
          for (final p in kids)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                ExcludeSemantics(
                  child: Icon(
                    p.isStale(t) ? Icons.warning_amber_rounded : Icons.phone_android_rounded,
                    color: p.isStale(t) ? AppColors.pendingText : AppColors.muted,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(nameOf(p.childId), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                      p.lastSeen == null ? l10n.lastSeenNever : l10n.lastSeen(formatSeenTime(p.lastSeen!, t, lang)),
                      style: const TextStyle(fontSize: 15),
                    ),
                    if (p.isStale(t))
                      Text(
                        l10n.deviceNotCheckingIn,
                        key: ValueKey('stale-${p.childId}'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.pendingText),
                      ),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 10),
          if (recent.isEmpty)
            Text(l10n.noFamilyAlerts, style: const TextStyle(fontSize: 15, color: AppColors.muted))
          else
            for (final e in recent)
              Container(
                key: ValueKey('familyEvent-${e.id}'),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.purpleSoft))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${nameOf(e.childId)} · ${formatSeenTime(e.at!, t, lang)}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  Text(familyEventText(e, l10n), style: const TextStyle(fontSize: 15, height: 1.4)),
                ]),
              ),
        ]),
      ),
    );
  }
}
