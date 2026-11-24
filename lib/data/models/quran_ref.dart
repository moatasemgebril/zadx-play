import '../catalog/surah_index.dart';
import 'surah.dart';

/// A range of whole ayat in one surah (Hafs numbering), e.g. Al-Ikhlas 112:1–4.
///
/// Used to play a licensed recitation of Quranic adhkar. Only metadata lives
/// here: the recited audio comes from the licensed recitation pipeline, and any
/// Quran text shown comes from QuranRepository (never typed by hand).
class QuranRef {
  const QuranRef({required this.surah, required this.fromAyah, required this.toAyah});

  final int surah;
  final int fromAyah;
  final int toAyah;

  int get ayahCount => toAyah - fromAyah + 1;

  /// Stable id of this range, e.g. `112:1-4` (also used to know which button is playing).
  String get key => '$surah:$fromAyah-$toAyah';

  @override
  bool operator ==(Object other) =>
      other is QuranRef && other.surah == surah && other.fromAyah == fromAyah && other.toAyah == toAyah;

  @override
  int get hashCode => Object.hash(surah, fromAyah, toAyah);

  @override
  String toString() => 'QuranRef($key)';
}

/// The surah metadata for [ref], or null when the surah is not in [index].
SurahInfo? surahOfRef(QuranRef ref, {List<SurahInfo> index = surahIndex}) {
  for (final s in index) {
    if (s.number == ref.surah) return s;
  }
  return null;
}

/// True when [ref] is a real range: the surah is in [index] (add its metadata
/// there first, e.g. Al-Baqarah 286 ayat, before referencing it) and
/// 1 ≤ fromAyah ≤ toAyah ≤ the surah's ayah count.
bool isValidQuranRef(QuranRef ref, {List<SurahInfo> index = surahIndex}) {
  final s = surahOfRef(ref, index: index);
  if (s == null) return false;
  return ref.fromAyah >= 1 && ref.fromAyah <= ref.toAyah && ref.toAyah <= s.ayahCount;
}
