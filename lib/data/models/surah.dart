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
  const Voice({required this.id, required this.name, required this.source, this.licenceConfirmed = false, this.credit});

  final String id;
  final Localized name;

  /// Asset path (adhan) or remote folder name (reciter).
  final String source;

  /// True only once the recording's licence is confirmed IN WRITING (owner
  /// decision). Reciters that are not confirmed are hidden from children in
  /// release builds — see `visibleReciters` in `data/catalog/quran.dart`.
  final bool licenceConfirmed;

  /// Attribution shown in the app when the licence requires it (e.g. CC BY / CC BY-SA).
  final String? credit;
}
