import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../services/family/device_removal.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../parent/parent_gate.dart';

/// Shows only [RemovedDeviceScreen] while this device is removed from the family (BACKLOG P1-3a).
/// Sits above the app router (app.dart), so no tab, Settings or Help page is reachable until a
/// parent sets the device up again. [onSetUpDone] runs after that (app.dart: open the Parent area).
class RemovedDeviceGate extends ConsumerWidget {
  const RemovedDeviceGate({super.key, required this.child, this.onSetUpDone});

  final Widget child;
  final VoidCallback? onSetUpDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(deviceRemovalProvider)) return child;
    return Navigator(
      key: const ValueKey('removedDeviceNavigator'),
      onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => RemovedDeviceScreen(onSetUpDone: onSetUpDone)),
    );
  }
}

/// Calm, child-friendly "this device was removed from the family" screen. No error code, no
/// store link and no family data (the old family's names are already deleted). Games stay locked
/// (`removedLockPolicy`); only the parent PIN leads on.
class RemovedDeviceScreen extends ConsumerStatefulWidget {
  const RemovedDeviceScreen({super.key, this.onSetUpDone});

  final VoidCallback? onSetUpDone;

  @override
  ConsumerState<RemovedDeviceScreen> createState() => _RemovedDeviceScreenState();
}

class _RemovedDeviceScreenState extends ConsumerState<RemovedDeviceScreen> {
  bool _busy = false;

  Future<void> _parentSetUp() async {
    if (_busy) return;
    final ok = await confirmParentPin(context, ref);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = widget.onSetUpDone;
    final removal = ref.read(deviceRemovalProvider.notifier);
    // The parent just entered the PIN: the parent area opens for linking the device again.
    ref.read(parentUnlockedProvider.notifier).unlock();
    // This screen is gone once the removed state ends: nothing below uses `ref` or `context`.
    await removal.parentSetUpAgain();
    done?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Child screen: bright background (the brand navy is for the splash and the parent area).
    return Scaffold(
      key: const Key('removedDeviceScreen'),
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ZadCard(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const ExcludeSemantics(child: Icon(Icons.family_restroom_rounded, size: 56, color: AppColors.purple)),
                  const SizedBox(height: 10),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.removedDeviceTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.purpleDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.removedDeviceBody,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, height: 1.5, color: AppColors.ink),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.removedDeviceLocked,
                    key: const Key('removedDeviceLockedNote'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('removedDeviceParentButton'),
                    onPressed: _busy ? null : _parentSetUp,
                    icon: const Icon(Icons.shield_rounded),
                    label: Text(l10n.removedDeviceParentButton),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
