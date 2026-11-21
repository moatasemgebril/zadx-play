import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/quran.dart';

void main() {
  test('exactly one adhan: the Prophet\'s Mosque recording (owner decision)', () {
    expect(availableMuezzins().map((m) => m.id), ['madinah_rec']);
  });

  test('the adhan audio file is bundled and its CC BY credit is kept', () {
    final m = availableMuezzins().single;
    expect(File(m.source).existsSync(), isTrue, reason: 'missing ${m.source}');
    expect(m.credit, isNotNull);
    expect(File('assets/audio/ADHAN-CREDITS.txt').readAsStringSync(), contains('ejaz215'));
  });

  test('any old saved voice falls back to the Madinah adhan', () {
    for (final old in ['zadx', 'aaqib', 'andrewler', 'makkah', null]) {
      expect(resolveMuezzin(old).id, 'madinah_rec');
    }
  });
}
