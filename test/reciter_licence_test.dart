import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/core/localized.dart';
import 'package:zadx/data/catalog/quran.dart';
import 'package:zadx/data/models/surah.dart';

const _pendingA = Voice(id: 'a', name: Localized('أ', 'A'), source: 'A');
const _confirmedB = Voice(id: 'b', name: Localized('ب', 'B'), source: 'B', licenceConfirmed: true);
const _pendingC = Voice(id: 'c', name: Localized('ج', 'C'), source: 'C');

void main() {
  group('reciter licence', () {
    test('no reciter is confirmed yet (pre-launch blocker)', () {
      expect(reciters, isNotEmpty);
      expect(reciters.where((r) => r.licenceConfirmed), isEmpty);
    });

    test('release build with none confirmed shows no reciter', () {
      expect(visibleReciters(releaseBuild: true), isEmpty);
      expect(visibleReciters(releaseBuild: true, all: const [_pendingA, _pendingC]), isEmpty);
    });

    test('release build with one confirmed shows only that reciter', () {
      final v = visibleReciters(releaseBuild: true, all: const [_pendingA, _confirmedB, _pendingC]);
      expect(v.map((r) => r.id), ['b']);
    });

    test('debug build shows all reciters, pending ones flagged', () {
      final v = visibleReciters(releaseBuild: false, all: const [_pendingA, _confirmedB, _pendingC]);
      expect(v.map((r) => r.id), ['a', 'b', 'c']);
      expect(v.where((r) => !r.licenceConfirmed).map((r) => r.id), ['a', 'c']);
      expect(visibleReciters(releaseBuild: false).length, reciters.length);
    });

    test('muezzins keep working and default to not confirmed', () {
      expect(muezzins, isNotEmpty);
      expect(muezzins.every((m) => m.source.isNotEmpty), isTrue);
    });
  });

  group('audio reciter fallback', () {
    test('never throws on an empty list and returns null', () {
      expect(() => resolveReciter('afasy', const []), returnsNormally);
      expect(resolveReciter('afasy', const []), isNull);
      expect(resolveReciter(null, const []), isNull);
      expect(resolveReciter('afasy', visibleReciters(releaseBuild: true)), isNull);
    });

    test('picks the saved reciter when visible, else the first visible one', () {
      const visible = [_pendingA, _confirmedB];
      expect(resolveReciter('b', visible)?.id, 'b');
      expect(resolveReciter('unknown', visible)?.id, 'a');
      expect(resolveReciter(null, visible)?.id, 'a');
    });
  });
}
