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
/// the foreground, a device where protection was set up reports its state to the backend
/// (`reportProtection`). The backend pushes newly appeared problems to the parent devices and sends
/// a "not checking in" alert when a device has been silent for a day. Only reason codes are sent —
/// never app names or usage.
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
});
