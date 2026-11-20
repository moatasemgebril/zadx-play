import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/quran.dart';

void main() {
  test('reciter ids are unique', () {
    final ids = reciters.map((r) => r.id).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('Abdul Rashid Sufi is listed and streams whole surahs', () {
    final sufi = reciters.firstWhere((r) => r.id == 'sufi');
    expect(sufi.name.of('ar'), 'عبد الرشيد صوفي');
    expect(sufi.perAyah, isFalse);
    expect(sufi.surahUrlFor(1), 'https://download.quranicaudio.com/quran/abdurrashid_sufi/001.mp3');
    expect(sufi.surahUrlFor(114), endsWith('/114.mp3'));
  });

  test('EveryAyah reciters stay per-ayah', () {
    for (final r in reciters.where((r) => r.id != 'sufi')) {
      expect(r.perAyah, isTrue, reason: r.id);
      expect(r.surahUrlFor(1), isNull);
      expect(r.source, isNotEmpty);
    }
  });
}
