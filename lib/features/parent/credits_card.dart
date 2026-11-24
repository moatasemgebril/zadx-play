import 'package:flutter/material.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../data/catalog/quran.dart';
import '../../shared/widgets/zad_widgets.dart';

/// Credits and sources, shown in the parent area only. Keeps the attribution
/// required by the adhan's CC BY 3.0 licence and by the Quran Foundation
/// approval, without showing it on the child's screens.
///
/// CC BY 3.0 attribution needs: author, title/source link, licence link and a
/// note of the changes made. The links are shown as selectable text (no tap
/// target), matching assets/audio/ADHAN-CREDITS.txt.
class CreditsCard extends StatelessWidget {
  const CreditsCard({super.key});

  /// Licence of the bundled adhan recording.
  static const adhanLicenceUrl = 'https://creativecommons.org/licenses/by/3.0/';

  /// Original file of the bundled adhan recording (Freesound 33937 by ejaz215).
  static const adhanSourceUrl =
      'https://commons.wikimedia.org/wiki/File:33937_ejaz215_call-to-prayer-from-the-prophet-s-mo.ogg';

  @override
  Widget build(BuildContext context) {
    final ar = context.lang == 'ar';
    final adhanCredit = availableMuezzins().first.credit;
    final lines = <String>[
      if (adhanCredit != null) ...[
        ar
            ? 'الأذان: تسجيل من المسجد النبوي — $adhanCredit (Freesound 33937)'
            : "Adhan: recording from the Prophet's Mosque — $adhanCredit (Freesound 33937)",
        ar
            ? 'التعديلات: قُصّر التسجيل، وضُبط مستوى الصوت، وحُوّل إلى MP3'
            : 'Changes: trimmed, loudness-normalised and converted to MP3',
        ar ? 'المصدر: $adhanSourceUrl' : 'Source: $adhanSourceUrl',
        ar ? 'الرخصة (CC BY 3.0): $adhanLicenceUrl' : 'Licence (CC BY 3.0): $adhanLicenceUrl',
      ],
      ar ? 'بيانات القرآن مقدمة من Quran Foundation' : 'Quran data provided by Quran Foundation',
    ];
    return ZadCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ar ? 'المصادر والحقوق' : 'Credits & sources', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(l, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
            ),
        ],
      ),
    );
  }
}
