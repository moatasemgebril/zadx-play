import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feature_flags.dart';
import '../../features/settings/settings_controller.dart';
import 'children_controller.dart';
import 'family_events.dart';
import 'family_repository.dart';

/// When this device last wrote its `lastSeen` (ms since epoch, device clock).
const presenceLastWriteKey = 'family.presence.lastWriteMs';

/// Child device (bound to one child), zero-cost backend: keeps `presence/{childId}.lastSeen`
/// fresh on start, on resume and every [presenceInterval] while open, at most one write per
/// [presenceInterval] (free Firestore quota). The parent app shows "last seen" from it and warns
/// when a device has been silent for over a day (this replaces the `checkHeartbeats` function).
/// A child paused on the Free plan is not monitored (docs/decisions/FREE-ONE-CHILD.md).
final presenceReporterProvider = Provider<void>((ref) {
  if (ref.watch(featureFlagsProvider).serverFunctions) return; // Blaze: reportProtection heartbeats
  final childId = ref.watch(childrenProvider.select((c) => c.boundChildId));
  if (childId == null) return;
  final repo = ref.watch(familyRepositoryProvider);
  final prefs = ref.watch(sharedPrefsProvider);

  Future<void> touch() async {
    try {
      if (ref.read(thisDevicePausedProvider)) return;
      final now = DateTime.now();
      final ms = prefs.getInt(presenceLastWriteKey);
      final last = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      if (!shouldTouchPresence(last, now)) return;
      await prefs.setInt(presenceLastWriteKey, now.millisecondsSinceEpoch);
      await repo.touchPresence(childId, platform: defaultTargetPlatform.name);
    } catch (e) {
      debugPrint('presence failed: $e');
    }
  }

  unawaited(touch());
  final listener = AppLifecycleListener(onResume: () => unawaited(touch()));
  final timer = Timer.periodic(presenceInterval, (_) => unawaited(touch()));
  ref.onDispose(() {
    listener.dispose();
    timer.cancel();
  });
});
