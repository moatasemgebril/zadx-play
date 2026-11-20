import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../features/settings/settings_controller.dart';
import 'audio_service.dart';

/// Short, child-friendly sound effects (all original, see assets/sfx/LICENSE.txt).
///
/// Any feature can play one with:
/// ```dart
/// ref.read(sfxProvider).play(Sfx.correct);
/// ```
enum Sfx { tap, correct, wrong, star, levelUp, taskComplete, unlock, transition }

extension SfxAsset on Sfx {
  String get asset => switch (this) {
        Sfx.tap => 'assets/sfx/tap.wav',
        Sfx.correct => 'assets/sfx/correct.wav',
        Sfx.wrong => 'assets/sfx/wrong.wav',
        Sfx.star => 'assets/sfx/star.wav',
        Sfx.levelUp => 'assets/sfx/level_up.wav',
        Sfx.taskComplete => 'assets/sfx/task_complete.wav',
        Sfx.unlock => 'assets/sfx/unlock.wav',
        Sfx.transition => 'assets/sfx/transition.wav',
      };
}

const musicAsset = 'assets/sfx/music_calm.wav';

// ---- pure rules (unit tested) -------------------------------------------------

/// Effects never play while the adhan or Quran recitation is playing.
bool shouldPlaySfx(PlayerKind kind, AppSettings settings) =>
    kind == PlayerKind.none && settings.soundEffectsOn && settings.sfxVolume > 0;

/// Background music only when the parent turned it on, nothing sacred is
/// playing, games are not locked for prayer, and the app is on screen.
bool shouldPlayMusic(
  PlayerKind kind,
  AppSettings settings, {
  bool prayerLock = false,
  bool inForeground = true,
}) =>
    kind == PlayerKind.none && settings.musicOn && settings.sfxVolume > 0 && !prayerLock && inForeground;

/// Effect loudness; quieter effects (transition) are already quiet in the file.
double sfxVolumeFor(AppSettings settings) => settings.sfxVolume.clamp(0.0, 1.0);

/// Music stays well under the effects.
double musicVolumeFor(AppSettings settings) => settings.sfxVolume.clamp(0.0, 1.0) * 0.35;

// ---- service --------------------------------------------------------------------

/// Plays effects from a small player pool (so quick sounds can overlap) and a
/// looping background pad. Never throws: audio problems only reach debugPrint.
class SfxService {
  SfxService(this._ref);

  final Ref _ref;

  static const poolSize = 4;
  static const _minGap = Duration(milliseconds: 60);

  final List<AudioPlayer> _pool = [];
  final List<String?> _loaded = [];
  int _next = 0;
  final Map<Sfx, DateTime> _lastPlayed = {};

  AudioPlayer? _music;
  bool _musicLoaded = false;
  bool _musicWanted = false;
  bool _prayerLock = false;
  bool _foreground = true;
  AppLifecycleListener? _lifecycle;
  Future<void> _musicOp = Future<void>.value();
  bool _disposed = false;

  PlayerKind get _kind => _ref.read(playerProvider).kind;
  AppSettings get _settings => _ref.read(settingsProvider);

  static AudioPlayer _newPlayer() => AudioPlayer(
        // Effects must not grab audio focus or pause other audio.
        handleInterruptions: false,
        handleAudioSessionActivation: false,
      );

  /// Plays [sfx] unless sounds are off or the adhan/Quran is playing.
  Future<void> play(Sfx sfx) async {
    if (_disposed) return;
    try {
      final settings = _settings;
      if (!shouldPlaySfx(_kind, settings)) return;
      final now = DateTime.now();
      final last = _lastPlayed[sfx];
      if (last != null && now.difference(last) < _minGap) return;
      _lastPlayed[sfx] = now;

      if (_pool.length < poolSize) {
        _pool.add(_newPlayer());
        _loaded.add(null);
      }
      final i = _next % _pool.length;
      _next = (_next + 1) % poolSize;
      final player = _pool[i];
      if (_loaded[i] != sfx.asset) {
        await player.setAsset(sfx.asset);
        _loaded[i] = sfx.asset;
      } else {
        await player.seek(Duration.zero);
      }
      await player.setVolume(sfxVolumeFor(settings));
      // Re-check: the adhan may have started while the asset was loading.
      if (_disposed || !shouldPlaySfx(_kind, _settings)) return;
      unawaited(player.play().catchError((Object e) => debugPrint('sfx play failed: $e')));
    } catch (e) {
      debugPrint('sfx ${sfx.name} failed: $e');
    }
  }

  /// Requests background music. It only actually plays when [shouldPlayMusic]
  /// allows it (parent setting on, no adhan/Quran, no prayer lock, app visible).
  Future<void> startMusic() {
    _musicWanted = true;
    _lifecycle ??= AppLifecycleListener(onStateChange: _onLifecycle);
    return _syncMusic();
  }

  Future<void> stopMusic() {
    _musicWanted = false;
    return _syncMusic();
  }

  /// Called by the sound coordinator when the prayer lock starts/ends.
  void setPrayerLock(bool locked) {
    if (_prayerLock == locked) return;
    _prayerLock = locked;
    _syncMusic();
  }

  void _onLifecycle(AppLifecycleState s) {
    _foreground = s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;
    _syncMusic();
  }

  void _onPlayerChanged(PlayerKind kind) {
    if (kind != PlayerKind.none) {
      // Adhan or Quran started: silence everything immediately.
      for (final p in _pool) {
        p.stop().catchError((Object e) => debugPrint('sfx stop failed: $e'));
      }
    }
    _syncMusic();
  }

  /// Serialised so rapid changes (adhan start + settings) never race.
  Future<void> _syncMusic() => _musicOp = _musicOp.then((_) => _applyMusic());

  Future<void> _applyMusic() async {
    if (_disposed) return;
    try {
      final settings = _settings;
      final want = _musicWanted &&
          shouldPlayMusic(_kind, settings, prayerLock: _prayerLock, inForeground: _foreground);
      if (!want) {
        final m = _music;
        if (m != null && m.playing) await m.pause();
        return;
      }
      final m = _music ??= _newPlayer();
      if (!_musicLoaded) {
        await m.setAsset(musicAsset);
        await m.setLoopMode(LoopMode.one);
        _musicLoaded = true;
      }
      await m.setVolume(musicVolumeFor(settings));
      if (!m.playing && shouldPlayMusic(_kind, _settings, prayerLock: _prayerLock, inForeground: _foreground)) {
        unawaited(m.play().catchError((Object e) => debugPrint('music play failed: $e')));
      }
    } catch (e) {
      debugPrint('music failed: $e');
    }
  }

  void dispose() {
    _disposed = true;
    _lifecycle?.dispose();
    for (final p in _pool) {
      p.dispose();
    }
    _music?.dispose();
  }
}

final sfxProvider = Provider<SfxService>((ref) {
  final service = SfxService(ref);
  ref.listen<PlayerKind>(playerProvider.select((s) => s.kind), (_, kind) => service._onPlayerChanged(kind));
  ref.listen<AppSettings>(settingsProvider, (prev, next) {
    if (prev == null ||
        prev.musicOn != next.musicOn ||
        prev.soundEffectsOn != next.soundEffectsOn ||
        prev.sfxVolume != next.sfxVolume) {
      service._syncMusic();
    }
  });
  ref.onDispose(service.dispose);
  return service;
});
