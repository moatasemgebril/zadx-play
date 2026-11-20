import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hook points for game feedback (sounds, haptics, analytics-free effects).
///
/// The sound system is built separately: override [eduGameHooksProvider]
/// (e.g. in main.dart's ProviderContainer) with an instance whose callbacks
/// play sounds. Every callback defaults to a no-op, and the games call them
/// at these moments:
/// - [onCorrect]: the child picked the right answer.
/// - [onWrong]: the child picked a wrong answer (keep this gentle).
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

final eduGameHooksProvider = Provider<EduGameHooks>((_) => const EduGameHooks());
