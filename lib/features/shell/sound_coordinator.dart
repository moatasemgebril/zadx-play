import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/audio/sfx_service.dart';
import '../../data/models/family_task.dart';
import '../tasks/wallet_controller.dart';

/// Which effect (if any) a wallet change deserves. Pure, unit tested.
///
/// - games become playable        → [Sfx.unlock]
/// - minutes/stars earned (approved) → [Sfx.star]
/// - child finished a task (waiting for approval) → [Sfx.taskComplete]
Sfx? walletSfx(WalletState? prev, WalletState next) {
  if (prev == null || prev.day != next.day) return null; // first load / new day: stay quiet
  if (!prev.gamesUnlocked && next.gamesUnlocked) return Sfx.unlock;
  if (next.earnedMinutes > prev.earnedMinutes) return Sfx.star;
  if (_finished(next) > _finished(prev)) return Sfx.taskComplete;
  return null;
}

int _finished(WalletState s) => s.tasks.where((t) => s.progressOf(t.id).status != TaskStatus.todo).length;

/// True when the visible location really changed (not the very first route).
bool isRouteChange(String? previous, String next) =>
    previous != null && previous.isNotEmpty && next.isNotEmpty && previous != next;

/// Listens to the wallet and plays effects.
/// Watched once from the app root, like the lock coordinator.
final soundCoordinatorProvider = Provider<void>((ref) {
  final sfx = ref.read(sfxProvider);
  ref.listen<WalletState>(walletProvider, (prev, next) {
    final effect = walletSfx(prev, next);
    if (effect != null) sfx.play(effect);
  });
});

/// Plays a very soft transition sound whenever the router's location changes
/// (tab switches, pushes and pops).
class RouteChangeSound {
  RouteChangeSound(this._router, this._onChange);

  final GoRouter _router;
  final VoidCallback _onChange;
  String? _last;

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
    if (isRouteChange(prev, loc)) _onChange();
  }
}
