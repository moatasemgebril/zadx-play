import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/services/app_lock/app_lock_service.dart';

/// Device-wide lock: docs/decisions/DEVICE-WIDE-LOCK.md
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const own = 'com.zadx.app';

  bool controls(String pkg, {LockMode mode = LockMode.allApps, Set<String> games = const {}, Set<String> allowed = const {}, Set<String> system = const {}}) =>
      lockRuleControls(
        pkg: pkg,
        ownPackage: own,
        mode: mode,
        selectedGames: games,
        parentAllowed: allowed,
        systemAllowed: system,
      );

  group('lock rule (mirror of LockRules.kt)', () {
    test('allApps locks unknown games, social apps and browsers', () {
      expect(controls('com.some.newgame'), isTrue);
      expect(controls('com.facebook.katana'), isTrue);
      expect(controls('com.android.chrome'), isTrue);
      expect(controls('com.google.android.youtube'), isTrue);
    });

    test('Zad X itself is never locked, in any mode', () {
      expect(controls(own), isFalse);
      expect(controls(own, mode: LockMode.selectedGames, games: {own}), isFalse);
    });

    test('phone, emergency and system UI are always allowed and cannot be removed', () {
      for (final pkg in [
        'com.android.phone',
        'com.android.server.telecom',
        'com.android.emergency',
        'com.android.systemui',
        'com.android.settings',
        'com.android.cellbroadcastreceiver',
      ]) {
        expect(controls(pkg), isFalse, reason: pkg);
      }
    });

    test('device roles resolved natively (dialer, launcher, keyboard, SMS) are allowed', () {
      const system = {'com.google.android.dialer', 'com.sec.android.app.launcher', 'com.google.android.inputmethod.latin'};
      for (final pkg in system) {
        expect(controls(pkg, system: system), isFalse, reason: pkg);
      }
    });

    test('parent allow-list opens extra apps', () {
      expect(controls('org.school.classroom', allowed: {'org.school.classroom'}), isFalse);
      expect(controls('org.school.other', allowed: {'org.school.classroom'}), isTrue);
    });

    test('legacy selectedGames mode locks only the selected games', () {
      const games = {'com.roblox.client'};
      expect(controls('com.roblox.client', mode: LockMode.selectedGames, games: games), isTrue);
      expect(controls('com.facebook.katana', mode: LockMode.selectedGames, games: games), isFalse);
    });

    test('empty package names are ignored', () {
      expect(controls(''), isFalse);
    });

    test('unknown stored modes fall back to the safer allApps', () {
      expect(LockMode.parse(null), LockMode.allApps);
      expect(LockMode.parse('nonsense'), LockMode.allApps);
      expect(LockMode.parse('selectedGames'), LockMode.selectedGames);
    });
  });

  group('LockPolicy', () {
    test('defaults to the device-wide lock with messaging allowed', () {
      const p = LockPolicy(locked: true, reason: 'requiredTasks', androidPackages: [], remainingMinutes: 0);
      expect(p.mode, LockMode.allApps);
      expect(p.allowedPackages, isEmpty);
      expect(p.allowMessaging, isTrue);
    });

    test('toMap carries mode, allow-list and messaging flag to native code', () {
      const p = LockPolicy(
        locked: false,
        reason: 'none',
        androidPackages: ['com.roblox.client'],
        remainingMinutes: 30,
        allowedPackages: ['org.school.classroom'],
        allowMessaging: false,
      );
      expect(p.toMap(), {
        'locked': false,
        'reason': 'none',
        'androidPackages': ['com.roblox.client'],
        'remainingMinutes': 30,
        'mode': 'allApps',
        'allowedPackages': ['org.school.classroom'],
        'allowMessaging': false,
      });
    });

    test('equality includes the new fields (so changes are pushed to native)', () {
      const a = LockPolicy(locked: true, reason: 'x', androidPackages: [], remainingMinutes: 0);
      const b = LockPolicy(locked: true, reason: 'x', androidPackages: [], remainingMinutes: 0, mode: LockMode.selectedGames);
      const c = LockPolicy(locked: true, reason: 'x', androidPackages: [], remainingMinutes: 0, allowedPackages: ['a']);
      const d = LockPolicy(locked: true, reason: 'x', androidPackages: [], remainingMinutes: 0, allowMessaging: false);
      expect(a == b, isFalse);
      expect(a == c, isFalse);
      expect(a == d, isFalse);
      expect(a, const LockPolicy(locked: true, reason: 'x', androidPackages: [], remainingMinutes: 0));
    });

    test('lockPolicyFrom derives mode and a sorted allow-list from settings', () {
      const s = AppSettings(allowedApps: {'z.app', 'a.app'}, allowMessaging: false);
      final p = lockPolicyFrom(locked: true, reason: 'prayer', remainingMinutes: 5, settings: s);
      expect(p.mode, LockMode.allApps);
      expect(p.allowedPackages, ['a.app', 'z.app']);
      expect(p.allowMessaging, isFalse);
      expect(p.androidPackages, isNotEmpty); // default selected games still passed for legacy mode
    });

    test('InstalledApp.listFrom ignores malformed native entries', () {
      final apps = InstalledApp.listFrom([
        {'package': 'a.b', 'label': 'AB'},
        {'package': 'c.d'},
        {'label': 'no package'},
        'junk',
      ]);
      expect(apps.map((a) => a.package), ['a.b', 'c.d']);
      expect(apps[1].label, 'c.d');
      expect(InstalledApp.listFrom(null), isEmpty);
    });
  });

  group('settings', () {
    Future<ProviderContainer> container() async {
      final prefs = await SharedPreferences.getInstance();
      return ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    }

    test('fresh install: device-wide lock on, messaging allowed, PC browsers locked', () async {
      SharedPreferences.setMockInitialValues({});
      final c = await container();
      addTearDown(c.dispose);
      final s = c.read(settingsProvider);
      expect(s.lockMode, LockMode.allApps);
      expect(s.allowedApps, isEmpty);
      expect(s.allowMessaging, isTrue);
      expect(s.pcAllowBrowsers, isFalse);
    });

    test('lock settings persist across restarts', () async {
      SharedPreferences.setMockInitialValues({});
      final first = await container();
      first.read(settingsProvider.notifier)
        ..setLockMode(LockMode.selectedGames)
        ..setAppAllowed('org.school.classroom', true)
        ..setAppAllowed('com.camera', true)
        ..setAppAllowed('com.camera', false)
        ..setAppAllowed('  ', true)
        ..setAllowMessaging(false)
        ..setPcAllowBrowsers(true);
      first.dispose();

      final second = await container();
      addTearDown(second.dispose);
      final s = second.read(settingsProvider);
      expect(s.lockMode, LockMode.selectedGames);
      expect(s.allowedApps, {'org.school.classroom'});
      expect(s.allowMessaging, isFalse);
      expect(s.pcAllowBrowsers, isTrue);
    });
  });
}
