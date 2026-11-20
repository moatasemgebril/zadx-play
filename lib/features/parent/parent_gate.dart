import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../settings/settings_controller.dart';

/// True after the parent entered the PIN in this app session.
final parentUnlockedProvider = StateProvider<bool>((_) => false);

String hashPin(String pin) => sha256.convert(utf8.encode('zadx:$pin')).toString();

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

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _ctrl.text.trim();
    if (pin.length < 4) return setState(() => _error = true);
    final stored = ref.read(settingsProvider).parentPinHash;
    if (stored == null) {
      ref.read(settingsProvider.notifier).setParentPinHash(hashPin(pin));
    } else if (stored != hashPin(pin)) {
      _ctrl.clear();
      return setState(() => _error = true);
    }
    ref.read(parentUnlockedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(parentUnlockedProvider)) return widget.child;
    final l10n = context.l10n;

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
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: InputDecoration(
                labelText: l10n.enterPin,
                errorText: _error ? l10n.wrongPin : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _submit, child: Text(l10n.approve)),
          ]),
        ),
      ),
    );
  }
}
