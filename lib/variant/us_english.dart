/// US English for Zad X Kids (US / Europe market, owner decision 2026-11-22).
///
/// Zad X Play keeps its British English. Zad X Kids shows US English instead:
/// * ARB strings: the Kids-visible keys with British wording are rewritten in `kidsRewrites`
///   (kids_strings.dart); test/kids_variant_test.dart fails if a British word is left;
/// * catalog and story text (`Localized.en`): [kidsUsEnglish] is applied by `Localized.of` in the
///   Kids build, so Play's text stays untouched.
library;

/// British → US English, most specific phrases first. Matched as whole words / phrases, any case;
/// a capital first letter is kept.
const List<(String, String)> kidsUsEnglishPhrases = [
  // Family words.
  ('ask your mum or dad', 'ask a parent or grown-up'),
  ('your mum or dad', 'a parent or grown-up'),
  ('mum or dad', 'a parent or grown-up'),
  ('your mum and dad', 'your parents'),
  ('mum and dad', 'parents'),
  ('mummy', 'mommy'),
  ('mums', 'moms'),
  ('mum', 'mom'),
  // School words.
  ('break time', 'recess'),
  ('end of term', 'end of the school year'),
  ('school term', 'school year'),
  ('term', 'school year'),
  ('head teacher', 'principal'),
  ('headteacher', 'principal'),
  ('pupils', 'students'),
  ('pupil', 'student'),
  ('maths', 'math'),
  ('timetable', 'schedule'),
  ('tidy your room', 'clean your room'),
  ('pocket money', 'allowance'),
  // Everyday words.
  ('summer holidays', 'summer vacation'),
  ('holidays', 'vacation'),
  ('holiday', 'vacation'),
  ('biscuits', 'cookies'),
  ('biscuit', 'cookie'),
  ('sweets', 'candy'),
  ('jumper', 'sweater'),
  ('torch', 'flashlight'),
  ('football', 'soccer'),
  ('autumn', 'fall'),
  ('rubbish', 'trash'),
  ('aeroplane', 'airplane'),
  // Spelling.
  ('colourful', 'colorful'),
  ('coloured', 'colored'),
  ('colours', 'colors'),
  ('colour', 'color'),
  ('favourites', 'favorites'),
  ('favourite', 'favorite'),
  ('neighbours', 'neighbors'),
  ('neighbour', 'neighbor'),
  ('behaviour', 'behavior'),
  ('honour', 'honor'),
  ('humour', 'humor'),
  ('flavour', 'flavor'),
  ('practising', 'practicing'),
  ('practised', 'practiced'),
  ('practise', 'practice'),
  ('organised', 'organized'),
  ('organise', 'organize'),
  ('recognise', 'recognize'),
  ('realise', 'realize'),
  ('memorised', 'memorized'),
  ('memorise', 'memorize'),
  ('centre', 'center'),
  ('theatre', 'theater'),
  ('metres', 'meters'),
  ('metre', 'meter'),
  ('learnt', 'learned'),
  ('grey', 'gray'),
  ('cosy', 'cozy'),
  ('tyre', 'tire'),
  ('licence', 'license'),
  ('travelled', 'traveled'),
  ('travelling', 'traveling'),
  ('programme', 'program'),
  ('catalogue', 'catalog'),
];

final List<(RegExp, String)> _patterns = [
  for (final (british, us) in kidsUsEnglishPhrases)
    (RegExp("(?<![A-Za-z'-])${RegExp.escape(british)}(?![A-Za-z'-])", caseSensitive: false), us),
];

final Map<String, String> _cache = {};

/// [text] in US English (see [kidsUsEnglishPhrases]).
String kidsUsEnglish(String text) {
  if (text.isEmpty) return text;
  final cached = _cache[text];
  if (cached != null) return cached;
  var s = text;
  for (final (re, us) in _patterns) {
    s = s.replaceAllMapped(re, (m) {
      final first = m[0]![0];
      final capital = first != first.toLowerCase();
      return capital ? us[0].toUpperCase() + us.substring(1) : us;
    });
  }
  if (_cache.length < 2000) _cache[text] = s;
  return s;
}

/// The British words / phrases left in [text] (empty = already US English).
List<String> britishWordsIn(String text) => [
      for (var i = 0; i < kidsUsEnglishPhrases.length; i++)
        if (_patterns[i].$1.hasMatch(text)) kidsUsEnglishPhrases[i].$1,
    ];
