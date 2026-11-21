import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/catalog/quran.dart';
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
      await _player.setAudioSource(playlist);
      state = ZadPlayerState(kind: PlayerKind.quran, surahNumber: surah.number);
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
