import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_ext.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/catalog/praise.dart';
import '../../../services/family/children_controller.dart';

/// One picker per app session so the same phrase never shows twice in a row.
final praisePickerProvider = Provider<PraisePicker>((ref) => PraisePicker());

/// Shown when the child completes a task: an Islamic praise phrase in the
/// child's form of address, plus [note] (e.g. "sent for approval"). No sound.
Future<void> showPraiseDialog(BuildContext context, WidgetRef ref, {required String note}) {
  final l10n = context.l10n;
  final address = ref.read(childrenProvider).active.address;
  final phrase = ref.read(praisePickerProvider).next(address, context.lang);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.star_rounded, color: Color(0xFFFFC83D), size: 56),
      title: Text(phrase, textAlign: TextAlign.center, style: AppTheme.display(26)),
      content: Text(
        note,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.muted),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.praiseContinue)),
      ],
    ),
  );
}
