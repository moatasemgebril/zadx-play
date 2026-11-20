import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/settings/settings_controller.dart';

/// Loads the verified Uthmani text of a surah and caches it on the device.
///
/// Source: Quran.com API v4 — `GET /api/v4/quran/verses/uthmani?chapter_number=N`.
/// The Quran text is never typed by hand in this codebase.
/// TODO(release): optionally bundle the Tanzil Uthmani text as an asset for
/// fully offline first launch, and keep the attribution required by its licence.
class QuranRepository {
  QuranRepository(this._prefs, {http.Client? client}) : _client = client ?? http.Client();

  final SharedPreferences _prefs;
  final http.Client _client;

  static const _base = 'https://api.quran.com/api/v4/quran/verses/uthmani';

  Future<List<String>> ayat(int surahNumber) async {
    final key = 'quran.uthmani.$surahNumber';
    final cached = _prefs.getStringList(key);
    if (cached != null && cached.isNotEmpty) return cached;

    final res = await _client.get(Uri.parse('$_base?chapter_number=$surahNumber'));
    if (res.statusCode != 200) {
      throw Exception('Quran API ${res.statusCode}');
    }
    final verses = (jsonDecode(res.body) as Map<String, dynamic>)['verses'] as List;
    final text = [for (final v in verses) (v as Map<String, dynamic>)['text_uthmani'] as String];
    await _prefs.setStringList(key, text);
    return text;
  }
}

final quranRepositoryProvider = Provider<QuranRepository>((ref) => QuranRepository(ref.watch(sharedPrefsProvider)));

final surahTextProvider = FutureProvider.family<List<String>, int>(
  (ref, number) => ref.watch(quranRepositoryProvider).ayat(number),
);
