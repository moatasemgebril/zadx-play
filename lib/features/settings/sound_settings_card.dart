import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../services/audio/sfx_service.dart';
import '../../shared/widgets/zad_widgets.dart';
import 'settings_controller.dart';

/// Parent area: sound effects and their volume (the app has no music).
class SoundSettingsCard extends ConsumerWidget {
  const SoundSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.soundTitle, style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.soundEffects, style: const TextStyle(fontSize: 16)),
          subtitle: Text(l10n.soundEffectsSub, style: const TextStyle(fontSize: 14)),
          value: s.soundEffectsOn,
          onChanged: ctrl.setSoundEffectsOn,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l10n.soundVolume, style: const TextStyle(fontSize: 16)),
        ),
        Slider(
          value: s.sfxVolume,
          divisions: 10,
          label: '${(s.sfxVolume * 100).round()}%',
          semanticFormatterCallback: (v) => '${(v * 100).round()}%',
          onChanged: s.soundEffectsOn ? ctrl.setSfxVolume : null,
          // Let the parent hear the new level.
          onChangeEnd: (_) => ref.read(sfxProvider).play(Sfx.star),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(l10n.soundSacredNote, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ),
      ]),
    );
  }
}
