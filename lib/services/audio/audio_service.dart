import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/catalog/quran.dart';
import '../../data/catalog/surah_index.dart';
import '../../data/models/surah.dart';
import '../../features/settings/settings_controller.dart';

enum PlayerKind { none, adhan, quran }

@immutable
class ZadPlayerState {
  const ZadPlayerState({this.kind = PlayerKind.none, this.surahNumber, this.index = 0, this.loading = false});

  final PlayerKind kind;
  final int? surahNumber;

  /// Current ayah index (Quran) or adhan phrase index (approximate).
  final int index;
  final bool loading;

  bool get isPlaying => kind != PlayerKind.none;
}

/// Plays the adhan (bundled licensed audio) and Quran recitation (streamed per ayah).
///
/// Quran audio source: EveryAyah per-ayah MP3s, e.g.
/// https://everyayah.com/data/Alafasy_128kbps/001001.mp3
/// Only reciters with `licenceConfirmed` are streamed in release builds.
/// TODO(release): confirm usage terms or host recitations on your own CDN.
class PlayerController extends Notifier<ZadPlayerState> {
  final AudioPlayer _player = AudioPlayer();

  @override
  ZadPlayerState build() {
    final sub = _player.currentIndexStream.listen((i) {
      if (i != null && state.kind == PlayerKind.quran) state = ZadPlayerState(kind: state.kind, surahNumber: state.surahNumber, index: i);
    });
    final done = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) stop();
    });
    final pos = _player.positionStream.listen((p) {
      if (state.kind == PlayerKind.adhan) {
        final total = _player.duration?.inMilliseconds ?? 0;
        if (total > 0) {
          final idx = (p.inMilliseconds / total * adhanPhrases.length).floor().clamp(0, adhanPhrases.length - 1);
          if (idx != state.index) state = ZadPlayerState(kind: PlayerKind.adhan, index: idx);
        }
      }
    });
    ref.onDispose(() {
      sub.cancel();
      done.cancel();
      pos.cancel();
      _player.dispose();
    });
    return const ZadPlayerState();
  }

  Future<void> playAdhan() async {
    final id = ref.read(settingsProvider).muezzinId;
    final voice = muezzins.firstWhere((v) => v.id == id, orElse: () => muezzins.first);
    state = const ZadPlayerState(kind: PlayerKind.adhan, loading: true);
    try {
      // iPhone Safari only allows audio that starts inside the tap itself: start
      // play() right away (it waits for the source) instead of after `await load`.
      final load = _player.setAudioSource(AudioSource.asset(voice.source));
      unawaited(_player.play());
      await load;
      state = const ZadPlayerState(kind: PlayerKind.adhan);
    } catch (e) {
      debugPrint('adhan audio failed: $e');
      state = const ZadPlayerState();
    }
  }

  /// Called right after the parent/child picks another reciter. If a surah is
  /// playing, it switches immediately to the new reciter at the same ayah, so
  /// there is no need to press pause first. Does nothing when nothing plays.
  Future<void> onReciterChanged() async {
    final target = reciterSwitchTarget(state);
    if (target == null) return;
    final surah = surahIndex.where((s) => s.number == target.surahNumber).firstOrNull;
    if (surah == null) return;
    // No `await stop()` first: on iPhone Safari any await before play() loses the tap.
    await playSurah(surah, startAyahIndex: target.ayahIndex);
  }

  /// Called right after another muezzin is picked: if the adhan is playing,
  /// restart it immediately with the new voice.
  Future<void> onMuezzinChanged() async {
    if (state.kind != PlayerKind.adhan) return;
    await playAdhan();
  }

  Future<void> playSurah(SurahInfo surah, {int startAyahIndex = 0}) async {
    final id = ref.read(settingsProvider).reciterId;
    // Release builds only stream reciters whose licence is confirmed in writing.
    final reciter = resolveReciter(id, visibleReciters());
    if (reciter == null) {
      // No licensed recitation yet: the screen shows "recitation coming soon".
      state = const ZadPlayerState();
      return;
    }
    state = ZadPlayerState(kind: PlayerKind.quran, surahNumber: surah.number, loading: true);
    final s = surah.number.toString().padLeft(3, '0');
    final playlist = ConcatenatingAudioSource(children: [
      for (var a = 1; a <= surah.ayahCount; a++)
        AudioSource.uri(Uri.parse(
          'https://everyayah.com/data/${reciter.source}/$s${a.toString().padLeft(3, '0')}.mp3',
        )),
    ]);
    try {
      final start = startAyahIndex.clamp(0, surah.ayahCount - 1);
      // iPhone Safari: call play() in the same tap, before the playlist finishes loading.
      final load = _player.setAudioSource(playlist, initialIndex: start);
      unawaited(_player.play());
      await load;
      state = ZadPlayerState(kind: PlayerKind.quran, surahNumber: surah.number, index: start);
    } catch (e) {
      debugPrint('quran audio failed: $e');
      state = const ZadPlayerState();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    state = const ZadPlayerState();
  }
}

/// Where to resume after a reciter change: the surah and ayah that were
/// playing, or null when no recitation is playing (pure, unit-tested).
({int surahNumber, int ayahIndex})? reciterSwitchTarget(ZadPlayerState s) {
  if (s.kind != PlayerKind.quran || s.surahNumber == null) return null;
  return (surahNumber: s.surahNumber!, ayahIndex: s.index < 0 ? 0 : s.index);
}

final playerProvider = NotifierProvider<PlayerController, ZadPlayerState>(PlayerController.new);
