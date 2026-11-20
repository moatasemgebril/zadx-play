import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/settings/settings_controller.dart';

Future<ProviderContainer> containerWith(SharedPreferences prefs) async =>
    ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sound defaults: effects on, music OFF, volume 0.6', () {
    const s = AppSettings();
    expect(s.soundEffectsOn, isTrue);
    expect(s.musicOn, isFalse);
    expect(s.sfxVolume, 0.6);
  });

  test('fresh install loads the same sound defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = await containerWith(prefs);
    addTearDown(c.dispose);
    final s = c.read(settingsProvider);
    expect(s.soundEffectsOn, isTrue);
    expect(s.musicOn, isFalse);
    expect(s.sfxVolume, 0.6);
  });

  test('sound settings persist across restarts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = await containerWith(prefs);
    first.read(settingsProvider.notifier)
      ..setSoundEffectsOn(false)
      ..setMusicOn(true)
      ..setSfxVolume(0.3);
    first.dispose();

    final second = await containerWith(prefs);
    addTearDown(second.dispose);
    final s = second.read(settingsProvider);
    expect(s.soundEffectsOn, isFalse);
    expect(s.musicOn, isTrue);
    expect(s.sfxVolume, 0.3);
  });

  test('volume is clamped to 0..1', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = await containerWith(prefs);
    addTearDown(c.dispose);
    final ctrl = c.read(settingsProvider.notifier);
    ctrl.setSfxVolume(3);
    expect(c.read(settingsProvider).sfxVolume, 1.0);
    ctrl.setSfxVolume(-1);
    expect(c.read(settingsProvider).sfxVolume, 0.0);
  });

  test('other settings survive copyWith of sound fields', () {
    const s = AppSettings(muezzinId: 'madinah', lockAtAdhan: false);
    final t = s.copyWith(musicOn: true, sfxVolume: 0.2);
    expect(t.muezzinId, 'madinah');
    expect(t.lockAtAdhan, isFalse);
    expect(t.soundEffectsOn, isTrue);
    expect(t.musicOn, isTrue);
    expect(t.sfxVolume, 0.2);
  });
}
