import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/shell/sound_coordinator.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/audio/audio_service.dart';
import 'package:zadx/services/audio/sfx_service.dart';

WalletState wallet(Map<String, TaskStatus> statuses, {bool prayerLock = false, String day = '2026-11-20'}) => WalletState(
      day: day,
      tasks: defaultTasks,
      progress: statuses.map((k, v) => MapEntry(k, TaskProgress(status: v))),
      prayerLock: prayerLock,
    );

void main() {
  group('no sound over the adhan or Quran', () {
    test('effects play only when nothing sacred is playing', () {
      expect(shouldPlaySfx(PlayerKind.none, const AppSettings()), isTrue);
      expect(shouldPlaySfx(PlayerKind.adhan, const AppSettings()), isFalse);
      expect(shouldPlaySfx(PlayerKind.quran, const AppSettings()), isFalse);
    });

    test('muted effects stay silent during adhan or Quran too', () {
      const muted = AppSettings(soundEffectsOn: false);
      expect(shouldPlaySfx(PlayerKind.adhan, muted), isFalse);
      expect(shouldPlaySfx(PlayerKind.quran, muted), isFalse);
    });
  });

  group('parent settings', () {
    test('effects are on by default', () {
      expect(shouldPlaySfx(PlayerKind.none, const AppSettings()), isTrue);
    });

    test('effects switch and zero volume silence effects', () {
      expect(shouldPlaySfx(PlayerKind.none, const AppSettings(soundEffectsOn: false)), isFalse);
      expect(shouldPlaySfx(PlayerKind.none, const AppSettings(sfxVolume: 0)), isFalse);
    });

    test('effect volume follows the parent setting, clamped to 0..1', () {
      expect(sfxVolumeFor(const AppSettings(sfxVolume: 0.3)), 0.3);
      expect(sfxVolumeFor(const AppSettings(sfxVolume: 1)), 1.0);
      expect(sfxVolumeFor(const AppSettings(sfxVolume: 2)), 1.0);
      expect(sfxVolumeFor(const AppSettings(sfxVolume: -1)), 0.0);
    });
  });

  test('every effect has a bundled asset', () {
    for (final s in Sfx.values) {
      expect(s.asset, startsWith('assets/sfx/'));
      expect(s.asset, endsWith('.wav'));
    }
  });

  group('wallet sounds', () {
    test('quiet on first load and on a new day', () {
      final s = wallet({'prayer': TaskStatus.done});
      expect(walletSfx(null, s), isNull);
      expect(walletSfx(wallet({}, day: '2026-11-19'), s), isNull);
    });

    test('child finishing a task plays taskComplete', () {
      expect(walletSfx(wallet({}), wallet({'pushup': TaskStatus.pending})), Sfx.taskComplete);
    });

    test('approval that earns minutes plays star', () {
      expect(
        walletSfx(wallet({'pushup': TaskStatus.pending}), wallet({'pushup': TaskStatus.done})),
        Sfx.star,
      );
    });

    test('games becoming playable plays unlock', () {
      final before = wallet({'prayer': TaskStatus.done, 'homework': TaskStatus.pending});
      final after = wallet({'prayer': TaskStatus.done, 'homework': TaskStatus.done});
      expect(walletSfx(before, after), Sfx.unlock);
    });

    test('prayer lock starting makes no sound', () {
      final before = wallet({'prayer': TaskStatus.done, 'homework': TaskStatus.done});
      final after = wallet({'homework': TaskStatus.done}, prayerLock: true);
      expect(walletSfx(before, after), isNull);
    });
  });

  test('route changes', () {
    expect(isRouteChange(null, '/home'), isFalse);
    expect(isRouteChange('', '/home'), isFalse);
    expect(isRouteChange('/home', '/home'), isFalse);
    expect(isRouteChange('/home', '/games'), isTrue);
  });
}
