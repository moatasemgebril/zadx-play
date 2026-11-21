import 'package:flutter/material.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../data/catalog/quran.dart';
import '../../shared/widgets/zad_widgets.dart';

/// Credits and sources, shown in the parent area only. Keeps the attribution
/// required by the adhan's CC BY 3.0 licence and by the Quran Foundation
/// approval, without showing it on the child's screens.
class CreditsCard extends StatelessWidget {
  const CreditsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ar = context.lang == 'ar';
    final adhanCredit = availableMuezzins().first.credit;
    final lines = <String>[
      if (adhanCredit != null)
        ar
            ? 'الأذان: تسجيل من المسجد النبوي — $adhanCredit (مع تحويل وتقصير)'
            : "Adhan: recording from the Prophet's Mosque — $adhanCredit (converted and trimmed)",
      ar ? 'بيانات القرآن مقدمة من Quran Foundation' : 'Quran data provided by Quran Foundation',
    ];
    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ar ? 'المصادر والحقوق' : 'Credits & sources', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          ),
      ]),
    );
  }
}
