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
  const Voice({required this.id, required this.name, required this.source});

  final String id;
  final Localized name;

  /// Asset path (adhan) or remote folder name (reciter).
  final String source;
}
