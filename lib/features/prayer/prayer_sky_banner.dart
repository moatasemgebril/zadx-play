import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/art/zad_art.dart';
import 'prayer_calculator.dart';
import 'prayer_providers.dart';

/// Decorative sky strip whose colours follow the prayer day
/// (Fajr dawn → Dhuhr day → Asr afternoon → Maghrib sunset → Isha night).
/// Reads the existing prayer providers only; never changes any state.
class PrayerSkyBanner extends ConsumerWidget {
  const PrayerSkyBanner({super.key, this.height = 64});
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final times = ref.watch(prayerTimesProvider);
    final now = ref.watch(cityNowProvider);
    final phase = prayerSkyPhaseFor(
      now: now.hours,
      fajr: times.of(Prayer.fajr),
      dhuhr: times.of(Prayer.dhuhr),
      asr: times.of(Prayer.asr),
      maghrib: times.of(Prayer.maghrib),
      isha: times.of(Prayer.isha),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ZadSceneBackground(scene: ZadScene.prayer, prayerPhase: phase, child: const SizedBox.expand()),
      ),
    );
  }
}
