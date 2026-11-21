import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The parent area unlocked by the PIN. It re-locks by itself (owner decision 2026-11-21):
/// * after [idleTimeout] without a touch in the parent area,
/// * immediately when Zad X goes to the background or the screen turns off
///   (`hidden` / `paused` / `detached`; Android and iOS report these when the screen locks).
///
/// `inactive` alone does not lock: it also fires for the App Store / Google Play purchase
/// sheet and system permission dialogs shown on top of the parent screens.
class ParentSession extends Notifier<bool> {
  static const idleTimeout = Duration(minutes: 2);

  Timer? _idle;

  @override
  bool build() {
    final listener = AppLifecycleListener(onStateChange: onLifecycle);
    ref.onDispose(() {
      _idle?.cancel();
      listener.dispose();
    });
    return false;
  }

  /// Called after the correct PIN.
  void unlock() {
    state = true;
    _restartIdle();
  }

  /// Any touch in the parent area keeps the session open for another [idleTimeout].
  void touch() {
    if (state) _restartIdle();
  }

  void lock() {
    _idle?.cancel();
    _idle = null;
    if (state) state = false;
  }

  @visibleForTesting
  void onLifecycle(AppLifecycleState s) {
    if (s == AppLifecycleState.hidden || s == AppLifecycleState.paused || s == AppLifecycleState.detached) lock();
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = Timer(idleTimeout, lock);
  }
}

/// True while the parent area is unlocked (see [ParentSession]).
final parentUnlockedProvider = NotifierProvider<ParentSession, bool>(ParentSession.new);
