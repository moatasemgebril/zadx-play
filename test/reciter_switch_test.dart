import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/services/audio/audio_service.dart';

void main() {
  group('reciterSwitchTarget', () {
    test('nothing playing: no switch', () {
      expect(reciterSwitchTarget(const ZadPlayerState()), isNull);
    });

    test('adhan playing: not a Quran switch', () {
      expect(reciterSwitchTarget(const ZadPlayerState(kind: PlayerKind.adhan, index: 3)), isNull);
    });

    test('Quran playing: resumes the same surah at the same ayah', () {
      final t = reciterSwitchTarget(const ZadPlayerState(kind: PlayerKind.quran, surahNumber: 67, index: 4));
      expect(t, isNotNull);
      expect(t!.surahNumber, 67);
      expect(t.ayahIndex, 4);
    });

    test('Quran playing while loading still switches', () {
      final t = reciterSwitchTarget(const ZadPlayerState(kind: PlayerKind.quran, surahNumber: 1, loading: true));
      expect(t!.surahNumber, 1);
      expect(t.ayahIndex, 0);
    });
  });
}
