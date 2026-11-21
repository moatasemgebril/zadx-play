import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/quran.dart';

void main() {
  test('at least one licensed adhan voice is available', () {
    expect(availableMuezzins(), isNotEmpty);
    expect(availableMuezzins().every((m) => m.licenceConfirmed), isTrue);
  });

  test('every available adhan voice has its audio file bundled', () {
    for (final m in availableMuezzins()) {
      expect(File(m.source).existsSync(), isTrue, reason: 'missing ${m.source}');
    }
  });

  test('unknown or unlicensed saved voice falls back to the first available', () {
    expect(resolveMuezzin('makkah').id, availableMuezzins().first.id);
    expect(resolveMuezzin(null).id, availableMuezzins().first.id);
    expect(resolveMuezzin('zadx').id, 'zadx');
  });
}
