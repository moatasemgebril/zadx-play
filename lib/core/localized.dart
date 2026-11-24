import '../variant/us_english.dart';
import 'app_variant.dart';

/// A short text available in the supported languages (used by static catalogs).
///
/// [en] is written once (British English, as in Zad X Play); the Zad X Kids build shows it in US
/// English ([kidsUsEnglish]), so catalog and story text needs no second copy.
class Localized {
  const Localized(this.ar, this.en);

  final String ar;
  final String en;

  String of(String lang) => lang == 'ar' ? ar : (kIsKids ? kidsUsEnglish(en) : en);

  /// The English text as Zad X Kids shows it (US English), in any build. For tests and previews.
  String get enKids => kidsUsEnglish(en);
}
