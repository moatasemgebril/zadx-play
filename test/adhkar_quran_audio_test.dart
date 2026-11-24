// Owner decision 2026-11-23: in the adhkar screen ONLY Quran ayat get a play button, recited by
// Mishary Alafasy through the licensed Quran pipeline (Quran Foundation approval 2026-11-21).
// Non-Quranic adhkar stay text-only (no licence for adhkar recordings).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/core/localized.dart';
import 'package:zadx/data/catalog/adhkar.dart';
import 'package:zadx/data/catalog/quran.dart';
import 'package:zadx/data/models/quran_ref.dart';
import 'package:zadx/data/models/surah.dart';
import 'package:zadx/features/adhkar/adhkar_view.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';
import 'package:zadx/services/audio/audio_service.dart';
import 'package:zadx/services/family/children_controller.dart';

/// Dhikr ids whose text is exactly whole Quran ayat. Empty today: see the note above `adhkar`
/// in lib/data/catalog/adhkar.dart (hasbi is only part of At-Tawbah 9:129).
const quranicDhikrIds = <String>{};

const _afasyPending = Voice(id: 'afasy', name: Localized('مشاري العفاسي', 'Mishary Alafasy'), source: 'Alafasy_128kbps');
const _basitConfirmed = Voice(id: 'basit', name: Localized('عبد الباسط', 'Abdul Basit'), source: 'B', licenceConfirmed: true);

Iterable<Dhikr> get _all => adhkar.values.expand((l) => l);

/// Records plays without a platform audio player. `online: false` behaves like a device with
/// no internet (the recitation cannot start).
class _FakePlayer extends PlayerController {
  _FakePlayer({this.online = true});
  final bool online;
  final played = <String>[];

  @override
  ZadPlayerState build() => const ZadPlayerState();

  @override
  Future<bool> playQuranRef(QuranRef r, Voice reciter) async {
    played.add('${reciter.id}:${r.key}');
    if (!online) return false;
    state = ZadPlayerState(kind: PlayerKind.quran, surahNumber: r.surah, refKey: r.key);
    return true;
  }

  @override
  Future<void> stop() async {
    state = const ZadPlayerState();
  }

  ZadPlayerState get current => state;
}

Future<void> _pump(WidgetTester tester, {required _FakePlayer player, bool withReciter = true, String lang = 'en'}) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'settings.language': lang});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 23, 8), 2)),
      activeChildIdProvider.overrideWithValue('child-1'),
      playerProvider.overrideWith(() => player),
      adhkarReciterProvider.overrideWithValue(withReciter ? adhkarReciter(releaseBuild: true) : null),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: AdhkarView()),
    ),
  ));
  await tester.pumpAndSettle();
}

AppLocalizations _l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(AdhkarView)));

void main() {
  group('Quran references', () {
    test('each Quran-referenced dhikr has a valid surah / ayah range', () {
      for (final d in _all.where((d) => d.quran != null)) {
        expect(isValidQuranRef(d.quran!), isTrue, reason: '${d.id} ${d.quran}');
      }
    });

    test('only Quranic entries have a reference', () {
      expect(_all.where((d) => d.quran != null).map((d) => d.id).toSet(), quranicDhikrIds);
      // Hasbi is only the second half of At-Tawbah 9:129: the recitation would not match the text.
      for (final id in ['m_hasbi', 'e_hasbi']) {
        expect(_all.firstWhere((d) => d.id == id).quran, isNull, reason: id);
      }
    });

    test('the Quls reminder plays Al-Ikhlas, Al-Falaq and An-Nas, whole', () {
      expect(qulsRefs.map((r) => r.key), ['112:1-4', '113:1-5', '114:1-6']);
      for (final r in qulsRefs) {
        expect(isValidQuranRef(r), isTrue, reason: r.key);
        expect(r.toAyah, surahOfRef(r)!.ayahCount, reason: r.key);
      }
    });

    test('invalid ranges are rejected', () {
      expect(isValidQuranRef(const QuranRef(surah: 112, fromAyah: 0, toAyah: 4)), isFalse);
      expect(isValidQuranRef(const QuranRef(surah: 112, fromAyah: 1, toAyah: 5)), isFalse);
      expect(isValidQuranRef(const QuranRef(surah: 113, fromAyah: 4, toAyah: 2)), isFalse);
      // Al-Baqarah needs its SurahInfo (286 ayat) before 2:255 or 2:285–286 can be referenced.
      expect(isValidQuranRef(const QuranRef(surah: 2, fromAyah: 255, toAyah: 255)), isFalse);
    });
  });

  group('reciter and licence', () {
    test('adhkar are recited by Alafasy, credited in Arabic and English', () {
      final v = adhkarReciter(releaseBuild: true);
      expect(v?.id, 'afasy');
      expect(v?.licenceConfirmed, isTrue);
      expect(reciterCredit(v!), 'مشاري العفاسي · Mishary Alafasy');
    });

    test('release build hides the button when the Alafasy licence is not confirmed, with no fallback', () {
      expect(adhkarReciter(releaseBuild: true, all: const [_afasyPending, _basitConfirmed]), isNull);
      expect(adhkarReciter(releaseBuild: false, all: const [_afasyPending, _basitConfirmed])?.id, 'afasy');
    });

    test('a reciter change on the Quran screen does not switch a playing dhikr', () {
      const s = ZadPlayerState(kind: PlayerKind.quran, surahNumber: 112, index: 1, refKey: '112:1-4');
      expect(reciterSwitchTarget(s), isNull);
    });

    test('per-ayah file of the shared recitation pipeline', () {
      expect(
        ayahAudioUri(adhkarReciter(releaseBuild: true)!, 112, 1).toString(),
        'https://everyayah.com/data/Alafasy_128kbps/112001.mp3',
      );
    });
  });

  group('adhkar screen', () {
    testWidgets('play buttons appear only for Quran ayat, with the reciter credit', (tester) async {
      await _pump(tester, player: _FakePlayer());
      // Morning or evening (by the clock): the Quls panel plus Quranic dhikr of that section (none today).
      final visibleSection = _all.where((d) => find.text(d.text).evaluate().isNotEmpty);
      final quranicVisible = visibleSection.where((d) => d.quran != null).length;
      expect(find.byType(QuranListenButton), findsNWidgets(qulsRefs.length + quranicVisible));
      for (final r in qulsRefs) {
        expect(find.byKey(QuranListenButton.keyFor(r)), findsOneWidget);
      }
      expect(find.text('مشاري العفاسي · Mishary Alafasy'), findsWidgets);
      // Every non-Quranic dhikr card stays text-only.
      for (final d in visibleSection.where((d) => d.quran == null)) {
        final card = find.ancestor(of: find.text(d.text), matching: find.byType(Column)).first;
        expect(find.descendant(of: card, matching: find.byType(QuranListenButton)), findsNothing, reason: d.id);
      }
    });

    testWidgets('salawat has no play button', (tester) async {
      await _pump(tester, player: _FakePlayer());
      await tester.tap(find.text(_l10n(tester).salawat));
      await tester.pumpAndSettle();
      expect(find.byType(QuranListenButton), findsNothing);
    });

    testWidgets('no licensed reciter: no play button and no credit', (tester) async {
      await _pump(tester, player: _FakePlayer(), withReciter: false);
      expect(find.byType(QuranListenButton), findsNothing);
      expect(find.text('مشاري العفاسي · Mishary Alafasy'), findsNothing);
    });

    testWidgets('play recites with Alafasy as Quran, then stop', (tester) async {
      final player = _FakePlayer();
      await _pump(tester, player: player);
      final ikhlas = find.byKey(QuranListenButton.keyFor(qulsRefs.first));
      await tester.tap(ikhlas);
      await tester.pumpAndSettle();
      expect(player.played, ['afasy:112:1-4']);
      expect(player.current.kind, PlayerKind.quran);
      expect(find.descendant(of: ikhlas, matching: find.byIcon(Icons.stop_rounded)), findsOneWidget);
      await tester.tap(ikhlas);
      await tester.pumpAndSettle();
      expect(player.current.kind, PlayerKind.none);
      expect(find.descendant(of: ikhlas, matching: find.byIcon(Icons.play_arrow_rounded)), findsOneWidget);
    });

    testWidgets('offline: a gentle inline hint, no error dialog', (tester) async {
      await _pump(tester, player: _FakePlayer(online: false));
      expect(find.text(_l10n(tester).quranListenOffline), findsNothing);
      await tester.tap(find.byKey(QuranListenButton.keyFor(qulsRefs[1])));
      await tester.pumpAndSettle();
      expect(find.text(_l10n(tester).quranListenOffline), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });
  });
}
