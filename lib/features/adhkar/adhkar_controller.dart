import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog/adhkar.dart';
import '../../data/models/family_task.dart';
import '../prayer/prayer_providers.dart';
import '../settings/settings_controller.dart';
import '../tasks/wallet_controller.dart';

/// Today's tasbeeh counts per dhikr id. Resets every day.
class AdhkarController extends Notifier<Map<String, int>> {
  static const _key = 'adhkar.counts';

  @override
  Map<String, int> build() {
    final day = ref.watch(cityNowProvider.select((n) => '${n.local.year}-${n.local.month}-${n.local.day}'));
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['day'] == day) return Map<String, int>.from(j['counts'] as Map);
    }
    return {};
  }

  void tap(AdhkarSection section, Dhikr d) {
    final current = state[d.id] ?? 0;
    if (current >= d.times) return;
    state = {...state, d.id: current + 1};
    _save();
    if (isSectionDone(section)) _onSectionDone(section);
  }

  void reset(Dhikr d) {
    state = {...state, d.id: 0};
    _save();
  }

  int count(String id) => state[id] ?? 0;

  bool isSectionDone(AdhkarSection section) => adhkar[section]!.every((d) => (state[d.id] ?? 0) >= d.times);

  void _onSectionDone(AdhkarSection section) {
    final taskId = switch (section) {
      AdhkarSection.morning => 'adhkar_morning',
      AdhkarSection.evening => 'adhkar_evening',
      AdhkarSection.salawat => null,
    };
    if (taskId == null) return;
    final wallet = ref.read(walletProvider);
    if (wallet.tasks.any((t) => t.id == taskId) && wallet.progressOf(taskId).status == TaskStatus.todo) {
      ref.read(walletProvider.notifier).submit(taskId);
    }
  }

  void _save() {
    final n = ref.read(cityNowProvider).local;
    ref.read(sharedPrefsProvider).setString(
          _key,
          jsonEncode({'day': '${n.year}-${n.month}-${n.day}', 'counts': state}),
        );
  }
}

final adhkarProvider = NotifierProvider<AdhkarController, Map<String, int>>(AdhkarController.new);
