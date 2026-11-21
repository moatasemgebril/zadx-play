import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/services/app_lock/app_lock_service.dart';

/// Device protection: docs/decisions/DEVICE-PROTECTION.md (mirror of LockRules.kt protection rules).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const own = 'com.zadx.app';
  const uninstallCls = 'com.android.packageinstaller.UninstallerActivity';

  ProtectionGuard guard(String pkg,
          {String? cls, bool settingsLock = true, bool uninstallGuard = true, bool window = false, Set<String> resolved = const {}}) =>
      protectionGuardFor(
        pkg: pkg,
        className: cls,
        ownPackage: own,
        settingsLock: settingsLock,
        uninstallGuard: uninstallGuard,
        parentWindowOpen: window,
        resolvedSettings: resolved,
      );

  group('Settings for the parent only', () {
    test('Settings (and settings search) are locked for the child by default', () {
      expect(guard('com.android.settings'), ProtectionGuard.settings);
      expect(guard('com.google.android.settings.intelligence'), ProtectionGuard.settings);
      expect(guard('com.vendor.settings', resolved: {'com.vendor.settings'}), ProtectionGuard.settings);
    });

    test('the PIN window opens Settings and the uninstall dialog', () {
      expect(guard('com.android.settings', window: true), ProtectionGuard.none);
      expect(guard('com.google.android.packageinstaller', cls: uninstallCls, window: true), ProtectionGuard.none);
    });

    test('the parent can switch the Settings lock off', () {
      expect(guard('com.android.settings', settingsLock: false), ProtectionGuard.none);
    });

    test('emergency, phone, system UI and Zad X are never covered, even if mis-resolved as settings', () {
      for (final pkg in [
        'com.android.phone',
        'com.android.server.telecom',
        'com.android.emergency',
        'com.google.android.apps.safetyhub',
        'com.android.cellbroadcastreceiver',
        'com.android.systemui',
        'com.google.android.permissioncontroller',
        'com.sec.android.app.safetyassurance',
        own,
      ]) {
        expect(guard(pkg, resolved: {pkg}), ProtectionGuard.none, reason: pkg);
      }
    });

    test('Kotlin and Dart always-allowed lists stay in sync for the safety core', () {
      expect(androidAlwaysAllowed, containsAll(['com.samsung.android.emergency', 'com.sec.android.app.safetyassurance']));
      expect(androidSettingsPackages, contains('com.android.settings'));
    });
  });

  group('Prevent deleting Zad X', () {
    test('uninstall dialog is covered only while the guard is on', () {
      expect(guard('com.google.android.packageinstaller', cls: uninstallCls), ProtectionGuard.uninstall);
      expect(guard('com.android.packageinstaller', cls: uninstallCls, settingsLock: false), ProtectionGuard.uninstall);
      expect(guard('com.google.android.packageinstaller', cls: uninstallCls, uninstallGuard: false), ProtectionGuard.none);
    });

    test('installing apps and other installer screens are not the uninstall dialog', () {
      expect(guard('com.google.android.packageinstaller', cls: 'com.android.packageinstaller.PackageInstallerActivity'),
          ProtectionGuard.none);
      expect(guard('com.some.game', cls: 'UninstallFakeActivity'), ProtectionGuard.none);
    });
  });

  group('tamper reasons', () {
    test('only protections that were on are reported', () {
      expect(protectionTamperReasons(ProtectionStatus.none, uninstallGuard: true), isEmpty);
      expect(
        protectionTamperReasons(
          const ProtectionStatus(platform: 'android', serviceEverEnabled: true, accessibility: false),
          uninstallGuard: false,
        ),
        ['accessibility_off'],
      );
      expect(
        protectionTamperReasons(
          const ProtectionStatus(platform: 'android', serviceEverEnabled: true, accessibility: true, adminEverEnabled: true),
          uninstallGuard: true,
        ),
        ['device_admin_off'],
      );
      expect(
        protectionTamperReasons(
          const ProtectionStatus(platform: 'android', serviceEverEnabled: true, accessibility: true, adminEverEnabled: true),
          uninstallGuard: false,
        ),
        isEmpty,
        reason: 'parent turned delete protection off with the PIN',
      );
      expect(
        protectionTamperReasons(const ProtectionStatus(platform: 'ios', authorizationEverApproved: true), uninstallGuard: false),
        ['screen_time_off'],
      );
    });

    test('ProtectionStatus.fromMap is defensive', () {
      expect(ProtectionStatus.fromMap(null).wasSetUp, isFalse);
      expect(ProtectionStatus.fromMap('junk').platform, 'none');
      final s = ProtectionStatus.fromMap({'platform': 'android', 'accessibility': true, 'serviceEverEnabled': true, 'windowSeconds': 120});
      expect(s.wasSetUp, isTrue);
      expect(s.accessibility, isTrue);
      expect(s.windowSeconds, 120);
    });
  });

  group('settings + native bridge', () {
    test('Settings lock is on and delete protection off by default; both persist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      expect(c.read(settingsProvider).lockDeviceSettings, isTrue);
      expect(c.read(settingsProvider).preventUninstall, isFalse);
      c.read(settingsProvider.notifier)
        ..setLockDeviceSettings(false)
        ..setPreventUninstall(true);
      final c2 = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
      expect(c2.read(settingsProvider).lockDeviceSettings, isFalse);
      expect(c2.read(settingsProvider).preventUninstall, isTrue);
    });

    test('AppLockService sends the protection calls the native side expects', () async {
      const channel = MethodChannel('test/app_lock');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'openParentWindow' => 300,
          'deviceAdminActive' => true,
          _ => null,
        };
      });
      final service = AppLockService(channel: channel);
      await service.setProtection(settingsLock: true, uninstallGuard: false);
      expect(await service.openParentWindow(), 300);
      expect(await service.deviceAdminActive(), isTrue);
      await service.closeParentWindow();
      expect(calls.map((c) => c.method), ['setProtection', 'openParentWindow', 'deviceAdminActive', 'closeParentWindow']);
      expect(calls.first.arguments, {'settingsLock': true, 'uninstallGuard': false});
      expect(calls[1].arguments, {'minutes': parentWindowMinutes});
      expect(parentWindowMinutes, lessThanOrEqualTo(maxParentWindowMinutes));
    });
  });
}
