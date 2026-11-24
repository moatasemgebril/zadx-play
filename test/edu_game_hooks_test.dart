import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/edu_games/edu_game_hooks.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/services/audio/audio_service.dart';
import 'package:zadx/services/audio/sfx_service.dart';

// Regression test for P0 "learning games have no sounds/haptics":
// eduGameHooksProvider was a no-op because nothing overrode it.

class _FakeSfx extends SfxService {
  _FakeSfx(super.ref, this.played);
  final List<Sfx> played;

  @override
  Future<void> play(Sfx sfx) async => played.add(sfx);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sounds', () {
    test('every game moment has a short effect, never music', () {
      expect(eduSfxFor(EduEvent.correct), Sfx.correct);
      expect(eduSfxFor(EduEvent.wrong), Sfx.wrong);
      expect(eduSfxFor(EduEvent.roundComplete), Sfx.winCombo);
      expect(eduSfxFor(EduEvent.partBuilt), Sfx.star);
      for (final e in EduEvent.values) {
        expect(eduSfxFor(e).asset, startsWith('assets/sfx/'));
        expect(eduSfxFor(e).asset.toLowerCase(), isNot(contains('music')));
      }
    });
  });

  group('haptics', () {
    const on = AppSettings();

    test('a wrong answer never vibrates', () {
      for (final kind in PlayerKind.values) {
        for (final s in const [AppSettings(), AppSettings(soundEffectsOn: false), AppSettings(sfxVolume: 1)]) {
          expect(eduHapticFor(EduEvent.wrong, kind, s), isNull);
        }
      }
    });

    test('happy moments give gentle feedback', () {
      expect(eduHapticFor(EduEvent.correct, PlayerKind.none, on), EduHaptic.light);
      expect(eduHapticFor(EduEvent.partBuilt, PlayerKind.none, on), EduHaptic.selection);
      expect(eduHapticFor(EduEvent.roundComplete, PlayerKind.none, on), EduHaptic.medium);
    });

    test('nothing while the adhan or Quran is playing', () {
      for (final e in EduEvent.values) {
        expect(eduHapticFor(e, PlayerKind.adhan, on), isNull);
        expect(eduHapticFor(e, PlayerKind.quran, on), isNull);
      }
    });

    test('nothing when the parent muted effects or set the volume to zero', () {
      for (final e in EduEvent.values) {
        expect(eduHapticFor(e, PlayerKind.none, const AppSettings(soundEffectsOn: false)), isNull);
        expect(eduHapticFor(e, PlayerKind.none, const AppSettings(sfxVolume: 0)), isNull);
      }
    });
  });

  group('wired hooks', () {
    test('play effects and haptics through the services', () {
      final played = <Sfx>[];
      final haptics = <EduHaptic>[];
      var kind = PlayerKind.none;
      var settings = const AppSettings();
      final hooks = buildEduGameHooks(
        playSfx: played.add,
        playerKind: () => kind,
        settings: () => settings,
        haptic: haptics.add,
      );

      hooks.onCorrect();
      hooks.onWrong();
      hooks.onRoundComplete(3);
      hooks.onPartBuilt();
      expect(played, [Sfx.correct, Sfx.wrong, Sfx.winCombo, Sfx.star]);
      expect(haptics, [EduHaptic.light, EduHaptic.medium, EduHaptic.selection]);

      // Adhan starts: the sound service stays in charge of silencing effects
      // (SfxService.play checks shouldPlaySfx), and no haptic fires.
      haptics.clear();
      kind = PlayerKind.adhan;
      hooks.onCorrect();
      expect(haptics, isEmpty);

      kind = PlayerKind.none;
      settings = const AppSettings(soundEffectsOn: false);
      hooks.onCorrect();
      expect(haptics, isEmpty);
    });

    test('earned stars give one coin ping each, after the win, no extra haptic', () {
      final played = <Sfx>[];
      final haptics = <EduHaptic>[];
      final delays = <Duration>[];
      final hooks = buildEduGameHooks(
        playSfx: played.add,
        playerKind: () => PlayerKind.none,
        settings: () => const AppSettings(),
        haptic: haptics.add,
        schedule: (d, action) {
          delays.add(d);
          action();
        },
      );

      hooks.onRoundComplete(3);
      hooks.onStarsEarned(3);
      expect(played, [Sfx.winCombo, Sfx.coin, Sfx.coin, Sfx.coin]);
      expect(delays, coinStreakDelays(3));
      expect(haptics, [EduHaptic.medium]);

      played.clear();
      hooks.onStarsEarned(0);
      expect(played, isEmpty);
    });

    test('the default provider is wired to the sound service (not a no-op)', () async {
      // Muted, so the test never touches the audio player or the vibration motor;
      // SfxService.play itself applies the mute.
      SharedPreferences.setMockInitialValues({'settings.language': 'en', 'settings.sfxOn': false});
      final prefs = await SharedPreferences.getInstance();
      final played = <Sfx>[];
      final c = ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        sfxProvider.overrideWith((ref) => _FakeSfx(ref, played)),
      ]);
      addTearDown(c.dispose);

      final hooks = c.read(eduGameHooksProvider);
      hooks.onCorrect();
      hooks.onWrong();
      hooks.onRoundComplete(2);
      hooks.onPartBuilt();
      expect(played, [Sfx.correct, Sfx.wrong, Sfx.winCombo, Sfx.star]);
    });
  });
}
