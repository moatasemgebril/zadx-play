// Regression test: the "excused" prayer pause was removed by owner decision 2026-11-22
// (branch remove/excused-pause). Prayer tasks and the prayer lock always apply; a legacy
// `prayerPaused` value saved by the removed feature is ignored. Firestore rules side:
// backend/functions/test/rules.test.js ("prayerPaused (removed excused pause) is not writable").
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/catalog/default_tasks.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/data/models/family_task.dart';
import 'package:zadx/features/prayer/prayer_calculator.dart';
import 'package:zadx/features/prayer/prayer_providers.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/features/tasks/wallet_controller.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/family_repository.dart';

const today = '2026-11-20';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prayer tasks always count: a required prayer task keeps games locked', () {
    final s = WalletState(day: today, tasks: defaultTasks, progress: const {}, approved: const {'homework': 20});
    expect(s.tasks.where((t) => t.kind == TaskKind.prayer), isNotEmpty);
    expect(s.requiredDone, isFalse);
    expect(s.gamesUnlocked, isFalse);
  });

  test('a legacy prayerPaused value is ignored and never written back', () {
    final day = FamilyDay.fromJson({
      'day': today,
      'progress': <String, dynamic>{},
      'usedMinutes': 0,
      'prayerLock': false,
      'prayerPaused': true,
    });
    expect(day.toJson().containsKey('prayerPaused'), isFalse);
  });

  test('legacy saved day with prayerPaused: the adhan still starts the prayer lock', () async {
    SharedPreferences.setMockInitialValues({
      'settings.language': 'en',
      ChildStorage.walletKey(ChildProfile.defaultId):
          jsonEncode({'day': today, 'progress': <String, dynamic>{}, 'usedMinutes': 0, 'prayerLock': false, 'prayerPaused': true}),
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      cityNowProvider.overrideWithValue(CityNow(DateTime(2026, 11, 20, 10), 2)),
      nextPrayerProvider.overrideWithValue(Prayer.dhuhr),
      familyRepositoryProvider.overrideWithValue(LocalFamilyRepository()),
    ]);
    addTearDown(container.dispose);

    container.read(walletProvider.notifier).startPrayerLock(Prayer.dhuhr);
    expect(container.read(walletProvider).prayerLock, isTrue);
    final saved = jsonDecode(prefs.getString(ChildStorage.walletKey(ChildProfile.defaultId))!) as Map<String, dynamic>;
    expect(saved.containsKey('prayerPaused'), isFalse);
  });

  test('the excused strings are gone from both ARB files and the Kids lists', () {
    for (final lang in const ['ar', 'en']) {
      final arb = jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;
      for (final key in const ['prayerPauseTitle', 'prayerPauseHelp', 'otherTasksOpenToday']) {
        expect(arb.containsKey(key), isFalse, reason: '$lang $key');
        expect(arb.containsKey('@$key'), isFalse, reason: '$lang @$key');
      }
    }
    final kids = File('lib/variant/kids_strings.dart').readAsStringSync() +
        File('lib/variant/kids_localizations.dart').readAsStringSync();
    expect(kids, isNot(contains('prayerPause')));
    expect(kids, isNot(contains('otherTasksOpenToday')));
  });
}
