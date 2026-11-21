import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/features/settings/settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Owner decision 2026-11-20: Zad X Play ships no background music.
  test('settings have no music and effects default on', () async {
    const d = AppSettings();
    expect(d.soundEffectsOn, isTrue);
    expect(d.sfxVolume, greaterThan(0));

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);
    c.read(settingsProvider.notifier)
      ..setSoundEffectsOn(true)
      ..setSfxVolume(0.5);
    expect(prefs.getKeys().where((k) => k.toLowerCase().contains('music')), isEmpty);
  });
}
