/// A short text available in the supported languages (used by static catalogs).
class Localized {
  const Localized(this.ar, this.en);

  final String ar;
  final String en;

  String of(String lang) => lang == 'ar' ? ar : en;
}
