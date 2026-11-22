import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Automated checks for lib/l10n/*.arb (app_ar.arb is the template):
// key parity, placeholder parity, ICU syntax, and count strings using ICU
// plurals with an int selector (never a String placeholder for the number).

Map<String, dynamic> _load(String locale) =>
    jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync()) as Map<String, dynamic>;

/// Count strings: the number changes the noun, so they must be ICU plurals.
const countKeys = [
  'minutesLeft',
  'gamesOpen',
  'psEarned',
  'deviceLockMinutes',
  'protectWindowOpen',
  'childSummary',
  'dhikrTimes',
  'ayatCount',
  'rewardMonths',
  'exReps',
  'childLimitBody',
];

const arabicPluralCases = {'zero', 'one', 'two', 'few', 'many', 'other'};
const numericTypes = {'int', 'num', 'double'};

// ---- a small ICU MessageFormat parser (the subset gen-l10n accepts) ---------

class IcuArg {
  IcuArg(this.name, [this.type, this.cases = const {}]);
  final String name;
  final String? type;
  final Map<String, List<Object>> cases;
}

class IcuParser {
  IcuParser(this.src);
  final String src;
  int _i = 0;

  static final _wordChar = RegExp(r'[A-Za-z0-9_]');
  static final _keyChar = RegExp(r'[A-Za-z0-9_=]');

  List<Object> parse() => _message(nested: false);

  List<Object> _message({required bool nested}) {
    final out = <Object>[];
    final buf = StringBuffer();
    while (_i < src.length) {
      final ch = src[_i];
      if (ch == '{') {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
        out.add(_argument());
      } else if (ch == '}') {
        if (!nested) _fail('unbalanced "}"');
        break;
      } else {
        buf.write(ch);
        _i++;
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  IcuArg _argument() {
    _i++; // {
    _ws();
    final name = _take(_wordChar);
    if (name.isEmpty) _fail('missing argument name');
    _ws();
    if (_peek == '}') {
      _i++;
      return IcuArg(name);
    }
    _expect(',');
    _ws();
    final type = _take(_wordChar);
    if (!const {'plural', 'select', 'selectordinal'}.contains(type)) _fail('unknown argument type "$type"');
    _ws();
    _expect(',');
    _ws();
    final cases = <String, List<Object>>{};
    while (_peek != '}') {
      if (_i >= src.length) _fail('unterminated "{$name, $type"');
      final key = _take(_keyChar);
      if (key.isEmpty) _fail('missing case key');
      _ws();
      _expect('{');
      final body = _message(nested: true);
      _expect('}');
      _ws();
      if (cases.containsKey(key)) _fail('duplicate case "$key"');
      cases[key] = body;
    }
    _i++; // }
    if (!cases.containsKey('other')) _fail('"{$name, $type}" has no "other" case');
    return IcuArg(name, type, cases);
  }

  String get _peek => _i < src.length ? src[_i] : '';

  void _ws() {
    while (_i < src.length && src[_i].trim().isEmpty) {
      _i++;
    }
  }

  String _take(RegExp char) {
    final start = _i;
    while (_i < src.length && char.hasMatch(src[_i])) {
      _i++;
    }
    return src.substring(start, _i);
  }

  void _expect(String c) {
    if (_peek != c) _fail('expected "$c"');
    _i++;
  }

  Never _fail(String message) => throw FormatException(message, src, _i);
}

Set<String> argNames(List<Object> nodes, [Set<String>? acc]) {
  final out = acc ?? <String>{};
  for (final n in nodes) {
    if (n is IcuArg) {
      out.add(n.name);
      for (final body in n.cases.values) {
        argNames(body, out);
      }
    }
  }
  return out;
}

Iterable<IcuArg> pluralArgs(List<Object> nodes) sync* {
  for (final n in nodes) {
    if (n is IcuArg) {
      if (n.type == 'plural' || n.type == 'selectordinal') yield n;
      for (final body in n.cases.values) {
        yield* pluralArgs(body);
      }
    }
  }
}

void main() {
  final ar = _load('ar');
  final en = _load('en');
  final arKeys = ar.keys.where((k) => !k.startsWith('@')).toSet();
  final enKeys = en.keys.where((k) => !k.startsWith('@')).toSet();

  Map<String, dynamic> placeholders(String key) =>
      ((ar['@$key'] as Map<String, dynamic>?)?['placeholders'] as Map<String, dynamic>?) ?? const {};
  String? typeOf(String key, String name) => (placeholders(key)[name] as Map<String, dynamic>?)?['type'] as String?;

  test('Arabic and English have the same keys', () {
    expect(arKeys.difference(enKeys), isEmpty, reason: 'missing in app_en.arb');
    expect(enKeys.difference(arKeys), isEmpty, reason: 'missing in app_ar.arb (the template)');
  });

  test('every message is valid ICU', () {
    for (final entry in [...ar.entries, ...en.entries]) {
      if (entry.key.startsWith('@')) continue;
      expect(() => IcuParser(entry.value as String).parse(), returnsNormally, reason: entry.key);
    }
  });

  test('placeholders match between Arabic and English and are declared', () {
    for (final key in arKeys) {
      final arNames = argNames(IcuParser(ar[key] as String).parse());
      final enNames = argNames(IcuParser(en[key] as String).parse());
      expect(enNames, arNames, reason: '$key: placeholders differ between ar and en');
      expect(arNames, placeholders(key).keys.toSet(), reason: '$key: used vs declared in "@$key"');
    }
  });

  test('plural selectors are numbers, never String placeholders', () {
    for (final key in arKeys) {
      for (final locale in [ar, en]) {
        for (final arg in pluralArgs(IcuParser(locale[key] as String).parse())) {
          expect(numericTypes, contains(typeOf(key, arg.name)), reason: '$key: "${arg.name}" selects a plural');
        }
      }
    }
  });

  group('count strings', () {
    for (final key in countKeys) {
      test('$key is an ICU plural on an int', () {
        final arNodes = IcuParser(ar[key] as String).parse();
        final enNodes = IcuParser(en[key] as String).parse();
        for (final nodes in [arNodes, enNodes]) {
          expect(nodes, hasLength(1), reason: '$key: the whole message is one plural');
          final arg = nodes.single as IcuArg;
          expect(arg.type, 'plural', reason: key);
          expect(typeOf(key, arg.name), 'int', reason: key);
        }
        expect((arNodes.single as IcuArg).cases.keys.toSet(), arabicPluralCases, reason: '$key (ar)');
        expect((enNodes.single as IcuArg).cases.keys.toSet(), containsAll(['one', 'other']), reason: '$key (en)');
      });
    }

    test('the Free plan reads "one child", not "1 children"', () {
      final arOne = (IcuParser(ar['childLimitBody'] as String).parse().single as IcuArg).cases['one']!.join();
      final enOne = (IcuParser(en['childLimitBody'] as String).parse().single as IcuArg).cases['one']!.join();
      expect(arOne, contains('طفل واحد بس'));
      expect(enOne, contains('1 child.'));
      expect(enOne, isNot(contains('children')));
    });

    test('trialDaysLeft has a last-day case', () {
      final arCases = (IcuParser(ar['trialDaysLeft'] as String).parse().single as IcuArg).cases;
      final enCases = (IcuParser(en['trialDaysLeft'] as String).parse().single as IcuArg).cases;
      expect(arCases['=0']!.join(), 'آخر يوم في التجربة');
      expect(enCases['=0']!.join(), 'Last day of your trial');
    });
  });

  group('wording', () {
    test('parent texts say "your child", not "your son"', () {
      for (final key in arKeys) {
        final v = ar[key] as String;
        expect(v, isNot(contains('ابنك')), reason: key);
        expect(v, isNot(contains('ابني ')), reason: key);
        expect(v, isNot(contains('ابني؟')), reason: key);
        expect((en[key] as String).toLowerCase(), isNot(contains('your son')), reason: key);
      }
    });

    test('no developer wording or stale trial length is shown to families', () {
      expect(ar['pairOffline'], isNot(contains('Firebase')));
      expect(en['pairOffline'], isNot(contains('Firebase')));
      expect(enKeys, isNot(contains('startTrial')));
      expect(enKeys, isNot(contains('gamesN')));
      for (final key in enKeys) {
        expect(en[key] as String, isNot(contains('14-day')), reason: key);
      }
    });
  });
}
