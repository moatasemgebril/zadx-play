import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zadx/data/catalog/praise.dart';
import 'package:zadx/data/models/child_profile.dart';

void main() {
  group('praise phrases', () {
    test('gender forms', () {
      const p = PraisePhrase(masculine: 'بارك الله فيك!', feminine: 'بارك الله فيكِ!', en: 'May Allah bless you!');
      expect(p.text(FormOfAddress.masculine, 'ar'), 'بارك الله فيك!');
      expect(p.text(FormOfAddress.feminine, 'ar'), 'بارك الله فيكِ!');
      expect(p.text(FormOfAddress.feminine, 'en'), 'May Allah bless you!');
      expect(p.text(FormOfAddress.masculine, 'en'), 'May Allah bless you!');
    });

    test('unset gender uses the masculine/neutral form', () {
      for (final p in praisePhrases) {
        expect(p.text(null, 'ar'), p.masculine);
        expect(p.text(null, 'en'), p.en);
      }
    });

    test('catalog has the six approved-for-review phrases, all non-empty', () {
      expect(praisePhrases.length, 6);
      for (final p in praisePhrases) {
        expect(p.masculine.trim(), isNotEmpty);
        expect(p.feminine.trim(), isNotEmpty);
        expect(p.en.trim(), isNotEmpty);
      }
      expect(praisePhrases.where((p) => p.feminine.contains('أحسنتِ')), hasLength(1));
    });

    test('picker never repeats the previous phrase', () {
      for (var seed = 0; seed < 20; seed++) {
        final picker = PraisePicker(Random(seed));
        String? prev;
        for (var i = 0; i < 200; i++) {
          final next = picker.next(FormOfAddress.feminine, 'ar');
          expect(next, isNot(prev));
          prev = next;
        }
      }
    });

    test('picker still varies and covers every phrase', () {
      final picker = PraisePicker(Random(1));
      final seen = {for (var i = 0; i < 300; i++) picker.next(null, 'en')};
      expect(seen, praisePhrases.map((p) => p.en).toSet());
    });

    test('picker with a single phrase returns it (no infinite loop)', () {
      const only = PraisePhrase(masculine: 'م', feminine: 'ف', en: 'e');
      final picker = PraisePicker(Random(0), const [only]);
      expect(picker.next(null, 'en'), 'e');
      expect(picker.next(null, 'en'), 'e');
    });
  });

  group('child form of address JSON', () {
    test('round-trips when set', () {
      for (final a in FormOfAddress.values) {
        final c = ChildProfile(id: 'c1', nickname: 'Sara', avatar: ChildAvatar.moon, address: a);
        final back = ChildProfile.tryFromJson(jsonDecode(jsonEncode(c.toJson())));
        expect(back, c);
        expect(back!.address, a);
      }
    });

    test('missing or unknown field reads as null (backwards compatible)', () {
      expect(ChildProfile.tryFromJson({'id': 'c1', 'nickname': 'Ali', 'avatar': 'sun'})!.address, isNull);
      expect(ChildProfile.tryFromJson({'id': 'c1', 'nickname': 'Ali', 'address': 'other'})!.address, isNull);
      expect(ChildProfile.tryFromJson({'id': 'c1', 'nickname': 'Ali', 'address': 3})!.address, isNull);
    });

    test('unset field is not written', () {
      const c = ChildProfile(id: 'c1', nickname: 'Ali');
      expect(c.toJson().containsKey('address'), isFalse);
    });

    test('copyWith keeps, changes and clears the address', () {
      const c = ChildProfile(id: 'c1', nickname: 'Huda', address: FormOfAddress.feminine);
      expect(c.copyWith(nickname: 'Noor').address, FormOfAddress.feminine);
      expect(c.copyWith(address: FormOfAddress.masculine).address, FormOfAddress.masculine);
      expect(c.copyWith(clearAddress: true).address, isNull);
    });
  });
}
