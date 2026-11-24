import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../onboarding/onboarding_pin_screen.dart';
import '../settings/settings_controller.dart';
import 'parent_session.dart';
import 'pin_security.dart';

export 'parent_session.dart' show parentUnlockedProvider;

/// Salted PBKDF2 hash for storing a new parent PIN (see [PinSecurity]).
String hashPin(String pin) => PinSecurity.hashPin(pin);

// Wrong-PIN counter and lock-out end, persisted so restarting the app does not reset them.
const _failuresKey = 'parent.pinFailures';
const _lockedUntilKey = 'parent.pinLockedUntil';

/// Shows [child] only after the parent PIN is entered.
///
/// The PIN is created only in onboarding ([FirstRunGate] / [OnboardingPinScreen]), never here:
/// this gate is reachable from child-facing entries ("Ask a parent"), so if no PIN exists it
/// shows a clear "for parents" card that opens the onboarding PIN step.
class ParentGate extends ConsumerStatefulWidget {
  const ParentGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<ParentGate> createState() => _ParentGateState();
}

class _ParentGateState extends ConsumerState<ParentGate> {
  final _ctrl = TextEditingController();
  bool _error = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTickerIfLocked();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Seconds left in the current lock-out (0 when the PIN may be tried).
  int _lockSecondsLeft() {
    final until = ref.read(sharedPrefsProvider).getInt(_lockedUntilKey) ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    // A lock-out longer than the maximum means the clock was moved back: keep the maximum.
    final capped = left.clamp(0, PinSecurity.lockoutFor(1000).inMilliseconds);
    return (capped / 1000).ceil();
  }

  void _startTickerIfLocked() {
    _ticker?.cancel();
    if (_lockSecondsLeft() <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_lockSecondsLeft() <= 0) t.cancel();
      setState(() {});
    });
  }

  void _recordFailure() {
    final prefs = ref.read(sharedPrefsProvider);
    final failures = (prefs.getInt(_failuresKey) ?? 0) + 1;
    prefs.setInt(_failuresKey, failures);
    final lock = PinSecurity.lockoutFor(failures);
    if (lock > Duration.zero) {
      prefs.setInt(_lockedUntilKey, DateTime.now().add(lock).millisecondsSinceEpoch);
      _startTickerIfLocked();
    }
  }

  void _submit() {
    if (_lockSecondsLeft() > 0) return;
    final pin = _ctrl.text.trim();
    if (pin.length < 4) return setState(() => _error = true);
    final settings = ref.read(settingsProvider.notifier);
    final stored = ref.read(settingsProvider).parentPinHash;
    // No PIN yet: never create one silently from here (a child could). See [openOnboardingPin].
    if (stored == null) return;
    if (!PinSecurity.verifyPin(pin, stored)) {
      _ctrl.clear();
      _recordFailure();
      return setState(() => _error = true);
    } else if (PinSecurity.needsUpgrade(stored)) {
      settings.setParentPinHash(PinSecurity.hashPin(pin)); // replace the old unsalted hash
    }
    final prefs = ref.read(sharedPrefsProvider);
    prefs.remove(_failuresKey);
    prefs.remove(_lockedUntilKey);
    _ctrl.clear();
    ref.read(parentUnlockedProvider.notifier).unlock();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(parentUnlockedProvider)) {
      // Every touch in the parent area restarts the 2-minute idle timer.
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => ref.read(parentUnlockedProvider.notifier).touch(),
        onPointerSignal: (_) => ref.read(parentUnlockedProvider.notifier).touch(),
        child: widget.child,
      );
    }
    final l10n = context.l10n;
    if (ref.watch(settingsProvider.select((s) => s.parentPinHash == null))) {
      return const _ParentSetupNeeded();
    }
    final lockedFor = _lockSecondsLeft();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ZadCard(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.shield_rounded, size: 48, color: AppColors.purple),
            const SizedBox(height: 8),
            Text(l10n.parentPin, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              enabled: lockedFor == 0,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                labelText: l10n.enterPin,
                errorText: lockedFor > 0
                    ? l10n.pinTooManyTries(lockedFor.toString())
                    : _error
                        ? l10n.wrongPin
                        : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: lockedFor > 0 ? null : _submit, child: Text(l10n.approve)),
          ]),
        ),
      ),
    );
  }
}

/// No parent PIN yet: a clear "for parents" card. Its button opens the onboarding PIN step;
/// nothing here can set a PIN by itself.
class _ParentSetupNeeded extends StatelessWidget {
  const _ParentSetupNeeded();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ZadCard(
          key: const Key('parentSetupNeeded'),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const ExcludeSemantics(child: Icon(Icons.family_restroom_rounded, size: 48, color: AppColors.purple)),
            const SizedBox(height: 8),
            Text(l10n.parentSetupNeededTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(l10n.parentSetupNeededBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('openOnboardingPin'),
              onPressed: () => openOnboardingPin(context),
              child: Text(l10n.parentSetupNeededButton),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Asks for the parent PIN again before a sensitive step, even inside the unlocked parent area
/// (the area may have been left open on the child's phone). Used to open the phone's Settings for
/// a few minutes and to turn device protection off (docs/decisions/DEVICE-PROTECTION.md).
/// Shares the wrong-PIN counter and lock-out with [ParentGate].
Future<bool> confirmParentPin(BuildContext context, WidgetRef ref) async {
  final stored = ref.read(settingsProvider).parentPinHash;
  if (stored == null) return false; // the PIN is created in onboarding (FirstRunGate)
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinConfirmDialog(stored: stored),
  );
  return ok == true;
}

class _PinConfirmDialog extends ConsumerStatefulWidget {
  const _PinConfirmDialog({required this.stored});
  final String stored;

  @override
  ConsumerState<_PinConfirmDialog> createState() => _PinConfirmDialogState();
}

class _PinConfirmDialogState extends ConsumerState<_PinConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int _lockSecondsLeft() {
    final until = ref.read(sharedPrefsProvider).getInt(_lockedUntilKey) ?? 0;
    final left = (until - DateTime.now().millisecondsSinceEpoch).clamp(0, PinSecurity.lockoutFor(1000).inMilliseconds);
    return (left / 1000).ceil();
  }

  void _submit() {
    if (_lockSecondsLeft() > 0) return setState(() => _error = true);
    final prefs = ref.read(sharedPrefsProvider);
    if (PinSecurity.verifyPin(_ctrl.text.trim(), widget.stored)) {
      prefs.remove(_failuresKey);
      prefs.remove(_lockedUntilKey);
      Navigator.pop(context, true);
      return;
    }
    final failures = (prefs.getInt(_failuresKey) ?? 0) + 1;
    prefs.setInt(_failuresKey, failures);
    final lock = PinSecurity.lockoutFor(failures);
    if (lock > Duration.zero) prefs.setInt(_lockedUntilKey, DateTime.now().add(lock).millisecondsSinceEpoch);
    _ctrl.clear();
    setState(() => _error = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lockedFor = _lockSecondsLeft();
    return AlertDialog(
      title: Text(l10n.parentPin),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 24, letterSpacing: 8),
        decoration: InputDecoration(
          labelText: l10n.enterPin,
          errorText: lockedFor > 0 ? l10n.pinTooManyTries(lockedFor.toString()) : (_error ? l10n.wrongPin : null),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.lockDisclosureCancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.approve)),
      ],
    );
  }
}
