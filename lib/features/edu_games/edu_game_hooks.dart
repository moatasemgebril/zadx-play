import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/audio/audio_service.dart';
import '../../services/audio/sfx_service.dart';
import '../settings/settings_controller.dart';

/// Hook points for game feedback (sounds, haptics, analytics-free effects).
///
/// [eduGameHooksProvider] is wired to the app's sound effects ([sfxProvider])
/// and haptics by default; tests can still override it. The games call these
/// callbacks at these moments:
/// - [onCorrect]: the child picked the right answer.
/// - [onWrong]: the child picked a wrong answer (kept gentle: soft sound, never a vibration).
/// - [onRoundComplete]: a round ended; the celebration screen is shown.
/// - [onPartBuilt]: a mosque part was added in Build Your Mosque.
class EduGameHooks {
  const EduGameHooks({
    this.onCorrect = _noop,
    this.onWrong = _noop,
    this.onRoundComplete = _noopStars,
    this.onPartBuilt = _noop,
  });

  final void Function() onCorrect;
  final void Function() onWrong;

  /// Receives the number of stars earned in the round (1–3).
  final void Function(int stars) onRoundComplete;
  final void Function() onPartBuilt;

  static void _noop() {}
  static void _noopStars(int stars) {}
}

/// Moments in a learning game that give feedback.
enum EduEvent { correct, wrong, roundComplete, partBuilt }

/// Kinds of haptic feedback the learning games use.
enum EduHaptic { light, selection, medium }

// ---- pure rules (unit tested) -------------------------------------------------

/// The sound effect for [event]. Effects only: Zad X Play has no music
/// (owner decision 2026-11-20).
Sfx eduSfxFor(EduEvent event) => switch (event) {
      EduEvent.correct => Sfx.correct,
      EduEvent.wrong => Sfx.wrong,
      EduEvent.roundComplete => Sfx.levelUp,
      EduEvent.partBuilt => Sfx.star,
    };

/// The haptic for [event], or null for none.
///
/// A wrong answer never vibrates (we stay kind). Haptics follow the same rules
/// as effects: none when the parent muted effects or set their volume to zero,
/// and none while the adhan or Quran recitation is playing.
EduHaptic? eduHapticFor(EduEvent event, PlayerKind kind, AppSettings settings) {
  if (!shouldPlaySfx(kind, settings)) return null;
  return switch (event) {
    EduEvent.correct => EduHaptic.light,
    EduEvent.wrong => null,
    EduEvent.roundComplete => EduHaptic.medium,
    EduEvent.partBuilt => EduHaptic.selection,
  };
}

void _platformHaptic(EduHaptic haptic) {
  final Future<void> done = switch (haptic) {
    EduHaptic.light => HapticFeedback.lightImpact(),
    EduHaptic.selection => HapticFeedback.selectionClick(),
    EduHaptic.medium => HapticFeedback.mediumImpact(),
  };
  done.catchError((Object _) {});
}

/// Builds hooks that play [eduSfxFor] through [playSfx] and [eduHapticFor]
/// through [haptic]. [playSfx] is expected to apply the sound rules itself
/// (mute, parent volume, silence during adhan/Quran), as [SfxService.play] does.
EduGameHooks buildEduGameHooks({
  required void Function(Sfx sfx) playSfx,
  required PlayerKind Function() playerKind,
  required AppSettings Function() settings,
  void Function(EduHaptic haptic) haptic = _platformHaptic,
}) {
  void fire(EduEvent event) {
    playSfx(eduSfxFor(event));
    final s = settings();
    // Muted: no haptics either, and no need to look at the adhan/Quran player.
    if (!s.soundEffectsOn || s.sfxVolume <= 0) return;
    final h = eduHapticFor(event, playerKind(), s);
    if (h != null) haptic(h);
  }

  return EduGameHooks(
    onCorrect: () => fire(EduEvent.correct),
    onWrong: () => fire(EduEvent.wrong),
    onRoundComplete: (_) => fire(EduEvent.roundComplete),
    onPartBuilt: () => fire(EduEvent.partBuilt),
  );
}

final eduGameHooksProvider = Provider<EduGameHooks>(
  (ref) => buildEduGameHooks(
    playSfx: (sfx) => ref.read(sfxProvider).play(sfx),
    playerKind: () => ref.read(playerProvider).kind,
    settings: () => ref.read(settingsProvider),
  ),
);
