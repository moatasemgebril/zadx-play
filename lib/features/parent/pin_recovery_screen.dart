import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../onboarding/onboarding_pin_screen.dart';
import '../settings/settings_controller.dart';
import 'parent_gate.dart';
import 'pin_recovery.dart';
import 'pin_security.dart';

/// The recovery-code store on this device ([PinRecoveryStore]).
final pinRecoveryStoreProvider = Provider<PinRecoveryStore>((ref) => PinRecoveryStore(ref.watch(sharedPrefsProvider)));

/// Buttons in these flows are at least 48 dp high (WCAG 2.2 target size; app theme may be absent).
const _minTarget = Size(48, 48);

/// Shows a new recovery code once and asks for its last 4 characters before [onConfirmed].
/// The code is held only in memory by the caller and is committed (hashed) after confirming.
class RecoveryCodeReveal extends StatefulWidget {
  const RecoveryCodeReveal({super.key, required this.code, required this.onConfirmed});
  final String code;
  final VoidCallback onConfirmed;

  @override
  State<RecoveryCodeReveal> createState() => _RecoveryCodeRevealState();
}

class _RecoveryCodeRevealState extends State<RecoveryCodeReveal> {
  final _confirm = TextEditingController();
  bool _mismatch = false;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_confirm.text.trim().toUpperCase() != RecoveryCode.lastFour(widget.code)) {
      _confirm.clear();
      setState(() => _mismatch = true);
      return;
    }
    _confirm.clear();
    widget.onConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Screen readers spell the code one character at a time.
    final spelled = widget.code.replaceAll('-', '').split('').join(' ');
    return Column(
      key: const Key('recoveryReveal'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExcludeSemantics(child: Icon(Icons.key_rounded, size: 48, color: AppColors.purple)),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(l10n.recoveryTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(14)),
          // The code is Latin: keep it left-to-right in Arabic too, so the groups stay in order.
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.code,
                key: const Key('recoveryCodeText'),
                semanticsLabel: l10n.recoveryCodeA11y(spelled),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.recoveryKeepAway,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.lockText, height: 1.4),
        ),
        const SizedBox(height: 4),
        Text(l10n.recoveryShownOnce, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5)),
        const SizedBox(height: 14),
        TextField(
          key: const Key('recoveryConfirmField'),
          controller: _confirm,
          maxLength: 4,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontSize: 22, letterSpacing: 6),
          decoration: InputDecoration(
            labelText: l10n.recoveryConfirmLabel,
            counterText: '',
            errorText: _mismatch ? l10n.recoveryConfirmMismatch : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const Key('recoveryConfirmButton'),
          style: FilledButton.styleFrom(minimumSize: _minTarget),
          onPressed: _submit,
          child: Text(l10n.recoveryConfirmButton),
        ),
      ],
    );
  }
}

/// Navy parent-area page with one white card (used by the recovery screens).
class _RecoveryPage extends StatelessWidget {
  const _RecoveryPage({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.navy,
        appBar: AppBar(
          backgroundColor: AppColors.navy,
          foregroundColor: Colors.white,
          title: Text(title),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ZadCard(child: child),
              ),
            ),
          ),
        ),
      );
}

/// Opens "Forgot PIN?" from the parent gate. Returns true when a new PIN was saved.
Future<bool> openForgotPin(BuildContext context) async {
  final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const ForgotPinScreen()),
  );
  return changed == true;
}

enum _ForgotStep { code, newPin, reveal }

/// "Forgot PIN?": recovery code → new PIN → new recovery code (the old one stops working).
/// Without a stored code it only explains the honest way out (clear data / reinstall) and has
/// no reset button at all, so a child cannot reset anything from here.
class ForgotPinScreen extends ConsumerStatefulWidget {
  const ForgotPinScreen({super.key});

  @override
  ConsumerState<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends ConsumerState<ForgotPinScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pinAgain = TextEditingController();
  _ForgotStep _step = _ForgotStep.code;
  RecoveryResult? _result;
  NewPinError? _pinError;
  String? _newPin;
  String? _newCode;
  Timer? _ticker;

  PinRecoveryStore get _store => ref.read(pinRecoveryStoreProvider);

  @override
  void initState() {
    super.initState();
    _startTickerIfLocked();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    _pin.dispose();
    _pinAgain.dispose();
    super.dispose();
  }

  void _startTickerIfLocked() {
    _ticker?.cancel();
    if (_store.lockSecondsLeft() <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_store.lockSecondsLeft() <= 0) t.cancel();
      setState(() {});
    });
  }

  void _checkCode() {
    final result = _store.check(_code.text);
    _code.clear();
    if (result == RecoveryResult.ok) {
      setState(() {
        _result = null;
        _step = _ForgotStep.newPin;
      });
      return;
    }
    setState(() => _result = result);
    _startTickerIfLocked();
  }

  void _saveNewPin() {
    final pin = _pin.text.trim();
    final error = validateNewPin(pin, _pinAgain.text.trim(), isParent: true);
    if (error != null) return setState(() => _pinError = error);
    _pin.clear();
    _pinAgain.clear();
    setState(() {
      _pinError = null;
      _newPin = pin;
      _newCode = RecoveryCode.generate();
      _step = _ForgotStep.reveal;
    });
  }

  Future<void> _finish() async {
    final pin = _newPin;
    final code = _newCode;
    if (pin == null || code == null) return;
    _newPin = null; // a second tap while saving does nothing
    final prefs = ref.read(sharedPrefsProvider);
    final settings = ref.read(settingsProvider.notifier);
    await _store.commit(code); // the old recovery code stops working here
    await prefs.remove(PinSecurity.failuresKey);
    await prefs.remove(PinSecurity.lockedUntilKey);
    settings.setParentPinHash(PinSecurity.hashPin(pin));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final Widget body;
    if (!_store.hasCode && _step == _ForgotStep.code) {
      body = Column(
        key: const Key('forgotNoCode'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ExcludeSemantics(child: Icon(Icons.info_rounded, size: 48, color: AppColors.purple)),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(l10n.forgotNoCodeTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 8),
          Text(l10n.forgotNoCodeBody, style: const TextStyle(fontSize: 16, height: 1.5)),
          const SizedBox(height: 8),
          Text(
            l10n.forgotNoCodeLoss,
            style: const TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w700, color: AppColors.lockText),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            key: const Key('forgotBack'),
            style: OutlinedButton.styleFrom(minimumSize: _minTarget),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.recoveryBack),
          ),
        ],
      );
    } else {
      body = switch (_step) {
        _ForgotStep.code => _codeStep(context),
        _ForgotStep.newPin => _newPinStep(context),
        _ForgotStep.reveal => RecoveryCodeReveal(code: _newCode!, onConfirmed: _finish),
      };
    }
    return _RecoveryPage(key: const Key('forgotPinScreen'), title: l10n.forgotPinTitle, child: body);
  }

  Widget _codeStep(BuildContext context) {
    final l10n = context.l10n;
    final lockedFor = _store.lockSecondsLeft();
    final errorText = lockedFor > 0
        ? l10n.pinTooManyTries(lockedFor.toString())
        : _result == RecoveryResult.wrong
            ? l10n.recoveryWrong
            : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ExcludeSemantics(child: Icon(Icons.key_rounded, size: 48, color: AppColors.purple)),
        const SizedBox(height: 8),
        Text(l10n.forgotPinEnterCode, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
        const SizedBox(height: 14),
        TextField(
          key: const Key('recoveryCodeInput'),
          controller: _code,
          enabled: lockedFor == 0,
          maxLength: 16,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]'))],
          style: const TextStyle(fontSize: 22, letterSpacing: 2),
          decoration: InputDecoration(
            labelText: l10n.recoveryCodeField,
            hintText: 'XXXX-XXXX-XXXX',
            counterText: '',
            errorText: errorText,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onSubmitted: (_) => _checkCode(), // a locked store refuses without counting
        ),
        const SizedBox(height: 10),
        FilledButton(
          key: const Key('recoveryCheckButton'),
          style: FilledButton.styleFrom(minimumSize: _minTarget),
          onPressed: lockedFor > 0 ? null : _checkCode,
          child: Text(l10n.recoveryCheck),
        ),
      ],
    );
  }

  Widget _newPinStep(BuildContext context) {
    final l10n = context.l10n;
    final errorText = switch (_pinError) {
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
    Widget pinField(Key key, TextEditingController c, String label, {ValueChanged<String>? onSubmitted}) => TextField(
          key: key,
          controller: c,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: deco(label),
          onSubmitted: onSubmitted,
        );
    return Column(
      key: const Key('recoveryNewPinStep'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(l10n.recoveryNewPinTitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 6),
        Text(l10n.recoveryNewPinBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.5)),
        const SizedBox(height: 14),
        pinField(const Key('recoveryNewPin'), _pin, l10n.onboardingPinNew),
        const SizedBox(height: 10),
        pinField(const Key('recoveryNewPinConfirm'), _pinAgain, l10n.onboardingPinAgain, onSubmitted: (_) => _saveNewPin()),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText,
              key: const Key('recoveryNewPinError'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.lockText),
            ),
          ),
        const SizedBox(height: 10),
        FilledButton(
          key: const Key('recoveryNewPinSave'),
          style: FilledButton.styleFrom(minimumSize: _minTarget),
          onPressed: _saveNewPin,
          child: Text(l10n.recoveryNewPinSave),
        ),
      ],
    );
  }
}

/// Creates (or replaces) the recovery code from the unlocked parent area. Closes itself when
/// the parent session locks (idle / app in background), so the code is never left on screen.
class RecoveryCodeSetupScreen extends ConsumerStatefulWidget {
  const RecoveryCodeSetupScreen({super.key});

  @override
  ConsumerState<RecoveryCodeSetupScreen> createState() => _RecoveryCodeSetupScreenState();
}

class _RecoveryCodeSetupScreenState extends ConsumerState<RecoveryCodeSetupScreen> {
  final String _code = RecoveryCode.generate();
  bool _closing = false;

  void _close(bool saved) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(saved);
  }

  Future<void> _confirmed() async {
    if (_closing) return;
    await ref.read(pinRecoveryStoreProvider).commit(_code);
    _close(true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(parentUnlockedProvider, (_, unlocked) {
      if (!unlocked) _close(false);
    });
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(parentUnlockedProvider.notifier).touch(),
      child: _RecoveryPage(
        key: const Key('recoverySetupScreen'),
        title: context.l10n.recoveryTitle,
        child: RecoveryCodeReveal(code: _code, onConfirmed: _confirmed),
      ),
    );
  }
}

/// Parent-area card: create a recovery code on installs that have none (non-blocking), or
/// replace a lost one. Asks for the PIN again first, because the parent area may have been
/// left open on the child's phone and a code lets its holder reset the PIN.
class RecoveryCodeCard extends ConsumerStatefulWidget {
  const RecoveryCodeCard({super.key});

  @override
  ConsumerState<RecoveryCodeCard> createState() => _RecoveryCodeCardState();
}

class _RecoveryCodeCardState extends ConsumerState<RecoveryCodeCard> {
  Future<void> _open() async {
    if (!await confirmParentPin(context, ref)) return;
    if (!mounted) return;
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const RecoveryCodeSetupScreen()),
    );
    if (!mounted) return;
    setState(() {});
    if (saved == true) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.recoverySaved)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final has = ref.read(pinRecoveryStoreProvider).hasCode;
    return ZadCard(
      key: Key(has ? 'recoveryCardSet' : 'recoveryCardMissing'),
      color: has ? null : AppColors.pendingBg,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
          child: Icon(has ? Icons.verified_user_rounded : Icons.key_rounded, size: 32, color: has ? AppColors.mintText : AppColors.pendingText),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(
              header: true,
              child: Text(
                has ? l10n.recoveryCardTitleSet : l10n.recoveryCardTitleMissing,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              has ? l10n.recoveryCardBodySet : l10n.recoveryCardBodyMissing,
              style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: has
                  ? OutlinedButton(
                      key: const Key('recoveryCardButton'),
                      style: OutlinedButton.styleFrom(minimumSize: _minTarget),
                      onPressed: _open,
                      child: Text(l10n.recoveryCardReplace),
                    )
                  : FilledButton(
                      key: const Key('recoveryCardButton'),
                      style: FilledButton.styleFrom(minimumSize: _minTarget),
                      onPressed: _open,
                      child: Text(l10n.recoveryCardCreate),
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}
