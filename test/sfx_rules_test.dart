import 'dart:io';
import 'dart:math';

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

  group('game-feel effects (coin, win combo, page)', () {
    test('every effect and coin variant exists on disk, small and not music', () {
      final assets = {for (final s in Sfx.values) s.asset, ...coinVariantAssets};
      for (final a in assets) {
        final f = File(a);
        expect(f.existsSync(), isTrue, reason: '$a missing: run python3 tools/gen_sfx.py');
        expect(f.lengthSync(), lessThan(120 * 1024), reason: '$a too big');
        expect(a.toLowerCase(), isNot(contains('music')));
      }
    });

    test('new effects are registered', () {
      expect(Sfx.coin.asset, 'assets/sfx/coin.wav');
      expect(Sfx.winCombo.asset, 'assets/sfx/win_combo.wav');
      expect(Sfx.transition.asset, 'assets/sfx/transition.wav');
      expect(coinVariantAssets, hasLength(4));
      expect(coinVariantAssets[1], Sfx.coin.asset);
    });

    test('every new sound is listed in the sfx licence as original', () {
      final licence = File('assets/sfx/LICENSE.txt').readAsStringSync();
      for (final a in {...coinVariantAssets, Sfx.winCombo.asset, Sfx.transition.asset}) {
        expect(licence, contains(a.split('/').last));
      }
    });

    test('coin pitch variant is random but never repeats back to back', () {
      final rng = Random(42);
      int? prev;
      final seen = <int>{};
      for (var i = 0; i < 200; i++) {
        final v = nextCoinVariant(prev, rng);
        expect(v, inInclusiveRange(0, coinVariantAssets.length - 1));
        if (prev != null) expect(v, isNot(prev));
        seen.add(v);
        prev = v;
      }
      expect(seen, hasLength(coinVariantAssets.length), reason: 'all variants get used');
      // Out-of-range previous values are treated as "none".
      expect(nextCoinVariant(-1, Random(1)), inInclusiveRange(0, 3));
      expect(nextCoinVariant(9, Random(1)), inInclusiveRange(0, 3));
    });

    test('sfxAssetFor picks coin variants and leaves other effects alone', () {
      expect(sfxAssetFor(Sfx.coin, variant: 0), 'assets/sfx/coin_lo.wav');
      expect(sfxAssetFor(Sfx.coin, variant: 3), 'assets/sfx/coin_hi.wav');
      expect(sfxAssetFor(Sfx.coin, variant: 99), 'assets/sfx/coin_hi.wav');
      expect(sfxAssetFor(Sfx.coin), Sfx.coin.asset);
      expect(sfxAssetFor(Sfx.winCombo, variant: 0), Sfx.winCombo.asset);
    });

    test('coin streak: one ping per star after the win, capped, never negative', () {
      expect(coinStreakDelays(0), isEmpty);
      expect(coinStreakDelays(-2), isEmpty);
      expect(coinStreakDelays(2), const [Duration(milliseconds: 700), Duration(milliseconds: 840)]);
      expect(coinStreakDelays(10), hasLength(3));
    });

    test('new effects still stay silent during adhan or Quran', () {
      // play() gates every effect, including coin/winCombo/transition, on this rule.
      expect(shouldPlaySfx(PlayerKind.adhan, const AppSettings()), isFalse);
      expect(shouldPlaySfx(PlayerKind.quran, const AppSettings()), isFalse);
    });
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

    test('approval that earns minutes plays the coin pickup', () {
      expect(
        walletSfx(wallet({'pushup': TaskStatus.pending}), wallet({'pushup': TaskStatus.done})),
        Sfx.coin,
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

  group('page sound', () {
    final t0 = DateTime(2026, 11, 23, 10);

    test('plays on a real page change', () {
      expect(shouldPlayRouteSound('/home', '/games', now: t0), isTrue);
      expect(shouldPlayRouteSound('/games', '/edu/letters', now: t0), isTrue);
      expect(shouldPlayRouteSound(null, '/home', now: t0), isFalse);
      expect(shouldPlayRouteSound('/home', '/home', now: t0), isFalse);
    });

    test('rapid taps are debounced', () {
      final soon = t0.add(const Duration(milliseconds: 100));
      final later = t0.add(routeSoundMinGap);
      expect(shouldPlayRouteSound('/games', '/tasks', lastPlayed: t0, now: soon), isFalse);
      expect(shouldPlayRouteSound('/games', '/tasks', lastPlayed: t0, now: later), isTrue);
    });

    test('quiet in the parent area, settings and the Quran tab', () {
      for (final r in ['/parent', '/settings', '/subscription', '/quran']) {
        expect(shouldPlayRouteSound('/home', r, now: t0), isFalse, reason: r);
      }
      // Coming back to a child page from the parent area sounds normally.
      expect(shouldPlayRouteSound('/parent', '/home', now: t0), isTrue);
    });
  });
}
