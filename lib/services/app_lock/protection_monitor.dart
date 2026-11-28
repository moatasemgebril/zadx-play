import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform.dart';
import '../../features/settings/settings_controller.dart';
import '../family/children_controller.dart';
import '../family/family_repository.dart';
import 'app_lock_service.dart';

/// Tamper alert (docs/decisions/DEVICE-PROTECTION.md): on start and every time Zad X comes back to
/// the foreground, a device where protection was set up reports its state (`reportProtection`).
/// Zero-cost backend (default): the state goes to `presence/{childId}` and each newly appeared
/// problem becomes one `protection` event that the parent app shows in-app and as a local
/// notification; the parent app also warns about a device silent for a day (presence_reporter.dart,
/// features/parent/family_alerts.dart). On Blaze the backend pushes instead. Only reason codes are
/// sent — never app names or usage.
final protectionMonitorProvider = Provider<void>((ref) {
  if (!AppPlatform.canLockGames) return;
  final service = ref.watch(appLockServiceProvider);

  Future<void> report() async {
    try {
      // A child paused on the Free plan is not monitored (docs/decisions/FREE-ONE-CHILD.md).
      if (ref.read(thisDevicePausedProvider)) return;
      final status = await service.protectionStatus();
      if (!status.wasSetUp) return;
      final reasons = protectionTamperReasons(
        status,
        uninstallGuard: ref.read(settingsProvider).preventUninstall,
      );
      await ref.read(familyRepositoryProvider).reportProtection(
            ref.read(activeChildIdProvider),
            platform: status.platform,
            reasons: reasons,
          );
    } catch (e) {
      debugPrint('protection report failed: $e');
    }
  }

  unawaited(report());
  final listener = AppLifecycleListener(onResume: () => unawaited(report()));
  ref.onDispose(listener.dispose);
  // Zad X Kids: the time / time zone was changed by hand while schedules are on (ClockChangeReceiver
  // -> lock coordinator). Report right away instead of on the next resume.
  ref.listen<int>(clockChangedTickProvider, (_, __) => unawaited(report()));
});
