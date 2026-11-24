import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
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
///
/// - [transition]: soft whoosh + tiny chime on page changes (see RouteChangeSound).
/// - [coin]: short point pickup when stars/minutes are awarded; a slightly
///   different pitch each time (see [nextCoinVariant]).
/// - [winCombo]: cascading sparkle run when a game round is won.
enum Sfx { tap, correct, wrong, star, levelUp, taskComplete, unlock, transition, coin, winCombo }

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
        Sfx.coin => 'assets/sfx/coin.wav',
        Sfx.winCombo => 'assets/sfx/win_combo.wav',
      };
}

/// Pitch variants of [Sfx.coin], rendered by tools/gen_sfx.py at playback-speed
/// ratios 0.95, 1.0, 1.04 and 1.08. Separate files instead of
/// `AudioPlayer.setSpeed`/`setPitch`: setSpeed keeps the pitch on Android, iOS
/// and web, and setPitch is Android-only. Index 1 is [Sfx.coin]'s own asset.
const coinVariantAssets = [
  'assets/sfx/coin_lo.wav',
  'assets/sfx/coin.wav',
  'assets/sfx/coin_up.wav',
  'assets/sfx/coin_hi.wav',
];

// ---- pure rules (unit tested) -------------------------------------------------

/// Effects never play while the adhan or Quran recitation is playing.
bool shouldPlaySfx(PlayerKind kind, AppSettings settings) =>
    kind == PlayerKind.none && settings.soundEffectsOn && settings.sfxVolume > 0;

/// Picks the next coin variant (index into [coinVariantAssets]): random, but
/// never the same as [previous], so a streak of pickups sounds alive.
/// [rng] is injected so tests are deterministic.
int nextCoinVariant(int? previous, Random rng) {
  final n = coinVariantAssets.length;
  if (previous == null || previous < 0 || previous >= n) return rng.nextInt(n);
  // Choose among the other n - 1 variants.
  final pick = rng.nextInt(n - 1);
  return pick >= previous ? pick + 1 : pick;
}

/// The asset to load for [sfx]; coins use [coinVariantAssets][variant].
String sfxAssetFor(Sfx sfx, {int variant = 1}) =>
    sfx == Sfx.coin ? coinVariantAssets[variant.clamp(0, coinVariantAssets.length - 1)] : sfx.asset;

/// When the coin pings of a round's [stars] play, after the win sound starts.
/// One ping per star (at most [maxPings]), starting near the end of the win
/// run and 140 ms apart, so the two sounds follow each other instead of
/// colliding. Empty for no stars.
List<Duration> coinStreakDelays(
  int stars, {
  Duration start = const Duration(milliseconds: 700),
  Duration gap = const Duration(milliseconds: 140),
  int maxPings = 3,
}) {
  final count = stars.clamp(0, maxPings);
  return [for (var i = 0; i < count; i++) start + gap * i];
}

/// Effect loudness; quieter effects (transition) are already quiet in the file.
double sfxVolumeFor(AppSettings settings) => settings.sfxVolume.clamp(0.0, 1.0);

// ---- service --------------------------------------------------------------------

/// Plays effects from a small player pool (so quick sounds can overlap).
/// The app has no background music. Never throws: audio problems only reach
/// debugPrint.
class SfxService {
  SfxService(this._ref);

  final Ref _ref;

  static const poolSize = 4;
  static const _minGap = Duration(milliseconds: 60);

  final List<AudioPlayer> _pool = [];
  final List<String?> _loaded = [];
  int _next = 0;
  final Map<Sfx, DateTime> _lastPlayed = {};
  final Random _rng = Random();
  int? _coinVariant;

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
      if (sfx == Sfx.coin) _coinVariant = nextCoinVariant(_coinVariant, _rng);
      final asset = sfxAssetFor(sfx, variant: _coinVariant ?? 1);
      // iPhone Safari only allows sound that starts inside the tap itself, so we
      // call play() right away (it waits for the asset) instead of after `await`.
      final Future<void> ready;
      if (_loaded[i] != asset) {
        _loaded[i] = asset;
        ready = player.setAsset(asset).then((_) {});
      } else {
        ready = player.seek(Duration.zero);
      }
      unawaited(player.setVolume(sfxVolumeFor(settings)));
      unawaited(player.play().catchError((Object e) => debugPrint('sfx play failed: $e')));
      await ready;
      // Re-check: the adhan may have started while the asset was loading.
      if (_disposed || !shouldPlaySfx(_kind, _settings)) await player.stop();
    } catch (e) {
      debugPrint('sfx ${sfx.name} failed: $e');
    }
  }

  void _onPlayerChanged(PlayerKind kind) {
    if (kind != PlayerKind.none) {
      // Adhan or Quran started: silence everything immediately.
      for (final p in _pool) {
        p.stop().catchError((Object e) => debugPrint('sfx stop failed: $e'));
      }
    }
  }

  void dispose() {
    _disposed = true;
    for (final p in _pool) {
      p.dispose();
    }
  }
}

final sfxProvider = Provider<SfxService>((ref) {
  final service = SfxService(ref);
  ref.listen<PlayerKind>(playerProvider.select((s) => s.kind), (_, kind) => service._onPlayerChanged(kind));
  ref.onDispose(service.dispose);
  return service;
});
