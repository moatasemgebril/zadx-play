import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../settings/settings_controller.dart';
import 'pin_security.dart';

/// True after the parent entered the PIN in this app session.
final parentUnlockedProvider = StateProvider<bool>((_) => false);

/// Salted PBKDF2 hash for storing a new parent PIN (see [PinSecurity]).
String hashPin(String pin) => PinSecurity.hashPin(pin);

// Wrong-PIN counter and lock-out end, persisted so restarting the app does not reset them.
const _failuresKey = 'parent.pinFailures';
const _lockedUntilKey = 'parent.pinLockedUntil';

/// Shows [child] only after the parent PIN is entered (or created the first time).
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
    if (stored == null) {
      settings.setParentPinHash(PinSecurity.hashPin(pin));
    } else if (!PinSecurity.verifyPin(pin, stored)) {
      _ctrl.clear();
      _recordFailure();
      return setState(() => _error = true);
    } else if (PinSecurity.needsUpgrade(stored)) {
      settings.setParentPinHash(PinSecurity.hashPin(pin)); // replace the old unsalted hash
    }
    final prefs = ref.read(sharedPrefsProvider);
    prefs.remove(_failuresKey);
    prefs.remove(_lockedUntilKey);
    ref.read(parentUnlockedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(parentUnlockedProvider)) return widget.child;
    final l10n = context.l10n;
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
