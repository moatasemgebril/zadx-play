import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../parent/pin_security.dart';
import '../settings/settings_controller.dart';

/// First-run gate: until a parent PIN exists, the whole app shows only the parent setup
/// screen, so child mode is never reachable without a PIN and a child can never create the
/// PIN from a child-facing entry ("Ask a parent" → [ParentGate]).
///
/// Used from `MaterialApp.router(builder: ...)` in app.dart. The screen gets its own
/// [Navigator] (text fields need an Overlay above them).
class FirstRunGate extends ConsumerWidget {
  const FirstRunGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPin = ref.watch(settingsProvider.select((s) => s.parentPinHash != null));
    if (hasPin) return child;
    return Navigator(
      key: const ValueKey('firstRunNavigator'),
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const OnboardingPinScreen()),
    );
  }
}

/// Opens the onboarding PIN step on top of the current screen (used by [ParentGate] when no
/// PIN exists). Returns true when a PIN was created.
Future<bool> openOnboardingPin(BuildContext context) async {
  final created = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const OnboardingPinScreen(popWhenDone: true)),
  );
  return created == true;
}

/// "For parents" onboarding step: create the parent PIN (4–6 digits, typed twice) and
/// confirm being the parent or guardian. Stored as a salted PBKDF2 hash ([PinSecurity]).
class OnboardingPinScreen extends ConsumerStatefulWidget {
  const OnboardingPinScreen({super.key, this.popWhenDone = false});

  /// Pop this route with `true` after saving (when opened with [openOnboardingPin]). On the
  /// first run the [FirstRunGate] swaps to the app by itself.
  final bool popWhenDone;

  @override
  ConsumerState<OnboardingPinScreen> createState() => _OnboardingPinScreenState();
}

/// Why a new parent PIN was refused ([validateNewPin]).
enum NewPinError { tooShort, mismatch, notParent }

class _OnboardingPinScreenState extends ConsumerState<OnboardingPinScreen> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  bool _isParent = false;
  NewPinError? _error;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _save() {
    final pin = _pin.text.trim();
    final again = _confirm.text.trim();
    final error = validateNewPin(pin, again, isParent: _isParent);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    ref.read(settingsProvider.notifier).setParentPinHash(PinSecurity.hashPin(pin));
    _pin.clear();
    _confirm.clear();
    if (widget.popWhenDone && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorText = switch (_error) {
      NewPinError.tooShort => l10n.onboardingPinTooShort,
      NewPinError.mismatch => l10n.onboardingPinMismatch,
      NewPinError.notParent => l10n.onboardingConfirmParentRequired,
      null => null,
    };
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        );

    return Scaffold(
      key: const Key('onboardingPinScreen'),
      backgroundColor: AppColors.navy,
      appBar: widget.popWhenDone
          ? AppBar(backgroundColor: AppColors.navy, foregroundColor: Colors.white)
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ZadCard(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(999)),
                      child: Text(l10n.forParentsBadge,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const ExcludeSemantics(child: Icon(Icons.shield_rounded, size: 48, color: AppColors.purple)),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    child: Text(l10n.onboardingPinTitle,
                        textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.onboardingPinBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('onboardingPin'),
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: deco(l10n.onboardingPinNew),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('onboardingPinConfirm'),
                    controller: _confirm,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: deco(l10n.onboardingPinAgain),
                    onSubmitted: (_) => _save(),
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    key: const Key('onboardingIsParent'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _isParent,
                    onChanged: (v) => setState(() => _isParent = v ?? false),
                    title: Text(l10n.onboardingIamParent, style: const TextStyle(fontSize: 16)),
                  ),
                  if (errorText != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(errorText,
                          key: const Key('onboardingPinError'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.lockText)),
                    ),
                  FilledButton(
                    key: const Key('onboardingPinSave'),
                    onPressed: _save,
                    child: Text(l10n.onboardingPinSave),
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.onboardingPinNote,
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.muted)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure check for a new parent PIN (unit-tested). Null = valid.
NewPinError? validateNewPin(String pin, String again, {required bool isParent}) {
  if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) return NewPinError.tooShort;
  if (pin != again) return NewPinError.mismatch;
  if (!isParent) return NewPinError.notParent;
  return null;
}
