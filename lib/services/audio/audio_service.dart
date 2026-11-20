import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/catalog/quran.dart';
import '../../data/models/surah.dart';
import '../../features/settings/settings_controller.dart';

enum PlayerKind { none, adhan, quran }

@immutable
class ZadPlayerState {
  const ZadPlayerState({
    this.kind = PlayerKind.none,
    this.surahNumber,
    this.index = 0,
    this.loading = false,
    this.progress,
  });

  final PlayerKind kind;
  final int? surahNumber;

  /// Current ayah index (Quran) or adhan phrase index (approximate).
  /// -1 while a whole-surah file plays: the current ayah is unknown, so none is highlighted.
  final int index;
  final bool loading;

  /// 0–1 playback progress for whole-surah recitations; null for per-ayah playback.
  final double? progress;

  bool get isPlaying => kind != PlayerKind.none;
}

/// Plays the adhan (bundled licensed audio) and Quran recitation (streamed per ayah).
///
/// Quran audio source: EveryAyah per-ayah MP3s, e.g.
/// https://everyayah.com/data/Alafasy_128kbps/001001.mp3
/// TODO(release): confirm usage terms or host recitations on your own CDN.
class PlayerController extends Notifier<ZadPlayerState> {
  final AudioPlayer _player = AudioPlayer();
  bool _wholeSurah = false;

  @override
  ZadPlayerState build() {
    final sub = _player.currentIndexStream.listen((i) {
      if (i != null && state.kind == PlayerKind.quran && !_wholeSurah) state = ZadPlayerState(kind: state.kind, surahNumber: state.surahNumber, index: i);
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
      } else if (state.kind == PlayerKind.quran && _wholeSurah && !state.loading) {
        final total = _player.duration?.inMilliseconds ?? 0;
        if (total > 0) {
          final progress = (p.inMilliseconds / total).clamp(0.0, 1.0);
          if ((progress - (state.progress ?? 0)).abs() >= 0.005) {
            state = ZadPlayerState(kind: PlayerKind.quran, surahNumber: state.surahNumber, index: -1, progress: progress);
          }
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
      await _player.setAudioSource(AudioSource.asset(voice.source));
      state = const ZadPlayerState(kind: PlayerKind.adhan);
      await _player.play();
    } catch (e) {
      debugPrint('adhan audio failed: $e');
      state = const ZadPlayerState();
    }
  }

  Future<void> playSurah(SurahInfo surah) async {
    final id = ref.read(settingsProvider).reciterId;
    final reciter = reciters.firstWhere((v) => v.id == id, orElse: () => reciters.first);
    final wholeUrl = reciter.surahUrlFor(surah.number);
    _wholeSurah = wholeUrl != null;
    state = ZadPlayerState(
      kind: PlayerKind.quran,
      surahNumber: surah.number,
      loading: true,
      index: _wholeSurah ? -1 : 0,
      progress: _wholeSurah ? 0 : null,
    );
    final s = surah.number.toString().padLeft(3, '0');
    final AudioSource source = wholeUrl != null
        ? AudioSource.uri(Uri.parse(wholeUrl))
        : ConcatenatingAudioSource(children: [
            for (var a = 1; a <= surah.ayahCount; a++)
              AudioSource.uri(Uri.parse(
                'https://everyayah.com/data/${reciter.source}/$s${a.toString().padLeft(3, '0')}.mp3',
              )),
          ]);
    try {
      await _player.setAudioSource(source);
      state = ZadPlayerState(
        kind: PlayerKind.quran,
        surahNumber: surah.number,
        index: _wholeSurah ? -1 : 0,
        progress: _wholeSurah ? 0 : null,
      );
      await _player.play();
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

final playerProvider = NotifierProvider<PlayerController, ZadPlayerState>(PlayerController.new);
