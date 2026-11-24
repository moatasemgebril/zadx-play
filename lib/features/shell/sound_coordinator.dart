import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/audio/sfx_service.dart';
import '../../data/models/family_task.dart';
import '../tasks/wallet_controller.dart';

/// Which effect (if any) a wallet change deserves. Pure, unit tested.
///
/// - games become playable        → [Sfx.unlock]
/// - minutes earned (parent approved a task) → [Sfx.coin] (point pickup)
/// - child finished a task (waiting for approval) → [Sfx.taskComplete]
Sfx? walletSfx(WalletState? prev, WalletState next) {
  if (prev == null || prev.day != next.day) return null; // first load / new day: stay quiet
  if (!prev.gamesUnlocked && next.gamesUnlocked) return Sfx.unlock;
  if (next.earnedMinutes > prev.earnedMinutes) return Sfx.coin;
  if (_finished(next) > _finished(prev)) return Sfx.taskComplete;
  return null;
}

int _finished(WalletState s) => s.tasks.where((t) => s.progressOf(t.id).status != TaskStatus.todo).length;

/// True when the visible location really changed (not the very first route).
bool isRouteChange(String? previous, String next) =>
    previous != null && previous.isNotEmpty && next.isNotEmpty && previous != next;

/// Pages that open without the game-style page sound:
/// - the parent area (PIN gate + dashboard), settings and subscription are
///   grown-up screens, where a playful whoosh would feel odd;
/// - the Quran tab, out of respect for the Mushaf.
/// Leaving one of them for a child page plays the sound as usual.
const quietRoutes = {'/parent', '/settings', '/subscription', '/quran'};

bool _isQuiet(String path) => quietRoutes.any((r) => path == r || path.startsWith('$r/'));

/// Rapid taps never spam the page sound: at most one per this interval.
const routeSoundMinGap = Duration(milliseconds: 350);

/// Whether a move from [previous] to [next] at [now] should play the page
/// sound, given when it last played ([lastPlayed], null = never). Pure, unit tested.
bool shouldPlayRouteSound(String? previous, String next, {DateTime? lastPlayed, required DateTime now}) {
  if (!isRouteChange(previous, next)) return false;
  if (_isQuiet(next)) return false;
  if (lastPlayed != null && now.difference(lastPlayed) < routeSoundMinGap) return false;
  return true;
}

/// Listens to the wallet and plays effects.
/// Watched once from the app root, like the lock coordinator.
final soundCoordinatorProvider = Provider<void>((ref) {
  final sfx = ref.read(sfxProvider);
  ref.listen<WalletState>(walletProvider, (prev, next) {
    final effect = walletSfx(prev, next);
    if (effect != null) sfx.play(effect);
  });
});

/// Plays the soft page sound ([Sfx.transition]) whenever the router's location
/// changes (tab switches, pushes and pops), following [shouldPlayRouteSound]:
/// debounced, and never into the parent area, settings or the Quran tab.
/// [SfxService.play] still applies mute, volume and the adhan/Quran silence.
class RouteChangeSound {
  RouteChangeSound(this._router, this._onChange);

  final GoRouter _router;
  final VoidCallback _onChange;
  String? _last;
  DateTime? _lastPlayed;

  void attach() {
    _last = _location();
    _router.routerDelegate.addListener(_handle);
  }

  void detach() => _router.routerDelegate.removeListener(_handle);

  String _location() {
    try {
      return _router.routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  void _handle() {
    final loc = _location();
    final prev = _last;
    _last = loc;
    final now = DateTime.now();
    if (!shouldPlayRouteSound(prev, loc, lastPlayed: _lastPlayed, now: now)) return;
    _lastPlayed = now;
    _onChange();
  }
}
