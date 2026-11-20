import '../../core/localized.dart';

/// Surah metadata (the text itself is loaded by QuranRepository).
class SurahInfo {
  const SurahInfo({required this.number, required this.name, required this.ayahCount, required this.juz});

  final int number;
  final Localized name;
  final int ayahCount;
  final int juz;
}

/// A muezzin or a Quran reciter.
class Voice {
  const Voice({required this.id, required this.name, required this.source, this.surahUrl});

  final String id;
  final Localized name;

  /// Asset path (adhan) or remote folder name (reciter).
  final String source;

  /// Whole-surah MP3 URL template with `{surah}` (3-digit surah number), for
  /// reciters that have no per-ayah recordings. When set, [source] is unused.
  final String? surahUrl;

  /// True when recitation is streamed one ayah at a time (ayah highlighting works).
  bool get perAyah => surahUrl == null;

  /// Whole-surah URL for [surahNumber], or null for per-ayah reciters.
  String? surahUrlFor(int surahNumber) =>
      surahUrl?.replaceAll('{surah}', surahNumber.toString().padLeft(3, '0'));
}
