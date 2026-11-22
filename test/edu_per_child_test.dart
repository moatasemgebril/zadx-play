import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/features/edu_games/letters/letters_progress.dart';
import 'package:zadx/features/edu_games/mosque/mosque_controller.dart';
import 'package:zadx/features/edu_games/stars_controller.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/children_controller.dart';

// Regression test for P1 "learning-game progress is shared by all siblings":
// stars, mosque parts and letters progress are now stored per child.

Future<(ProviderContainer, SharedPreferences)> makeContainer([Map<String, Object> initial = const {}]) async {
  SharedPreferences.setMockInitialValues({'settings.language': 'en', ...initial});
  final prefs = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPrefsProvider.overrideWithValue(prefs)]);
  addTearDown(c.dispose);
  return (c, prefs);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each child has their own stars, mosque and letters progress', () async {
    final (c, prefs) = await makeContainer();
    const first = ChildProfile.defaultId;
    expect(c.read(activeChildIdProvider), first);

    c.read(starsProvider.notifier).earn(5);
    expect(c.read(mosqueProvider.notifier).buildNext(), BuildResult.built); // foundation costs 2
    c.read(lettersProgressProvider.notifier).record(1, 3);
    expect(c.read(starsProvider), 3);

    final kids = c.read(childrenProvider.notifier);
    expect(kids.add('Maryam', ChildAvatar.flower, maxChildren: 5), AddChildResult.added);
    final second = c.read(childrenProvider).children.last.id;
    kids.select(second);

    // A sibling starts from zero.
    expect(c.read(starsProvider), 0);
    expect(c.read(mosqueProvider), 0);
    expect(c.read(lettersProgressProvider), isEmpty);
    expect(c.read(lettersProgressProvider.notifier).isUnlocked(2), isFalse);
    c.read(starsProvider.notifier).earn(1);

    // Switching back shows the first child's own progress, untouched.
    kids.select(first);
    expect(c.read(starsProvider), 3);
    expect(c.read(mosqueProvider), 1);
    expect(c.read(lettersProgressProvider)[1], 3);

    expect(prefs.getInt(ChildStorage.eduStarsKey(first)), 3);
    expect(prefs.getInt(ChildStorage.eduStarsKey(second)), 1);
    expect(prefs.getInt(ChildStorage.eduMosqueKey(first)), 1);
    expect(prefs.containsKey(ChildStorage.legacyEduStarsKey), isFalse);
  });

  test('removing a child deletes their learning progress', () async {
    final (c, prefs) = await makeContainer();
    final kids = c.read(childrenProvider.notifier);
    kids.add('Yusuf', ChildAvatar.rocket, maxChildren: 5);
    final yusuf = c.read(childrenProvider).children.last.id;
    kids.select(yusuf);
    c.read(starsProvider.notifier).earn(4);
    c.read(lettersProgressProvider.notifier).record(1, 2);
    expect(prefs.getInt(ChildStorage.eduStarsKey(yusuf)), 4);

    expect(kids.remove(yusuf), isTrue);
    expect(prefs.containsKey(ChildStorage.eduStarsKey(yusuf)), isFalse);
    expect(prefs.containsKey(ChildStorage.eduLettersKey(yusuf)), isFalse);
  });

  group('one-time migration of the old shared progress', () {
    test('moves to the active child and is removed from the shared keys', () async {
      final (c, prefs) = await makeContainer({
        ChildStorage.legacyEduStarsKey: 7,
        ChildStorage.legacyEduMosqueKey: 2,
        ChildStorage.legacyEduLettersKey: ['1:3', '2:1'],
      });
      const first = ChildProfile.defaultId;

      // Loading any one game moves all three values together.
      expect(c.read(starsProvider), 7);
      expect(prefs.getInt(ChildStorage.eduMosqueKey(first)), 2);
      expect(prefs.getStringList(ChildStorage.eduLettersKey(first)), ['1:3', '2:1']);
      expect(c.read(mosqueProvider), 2);
      expect(c.read(lettersProgressProvider), {1: 3, 2: 1});

      expect(prefs.containsKey(ChildStorage.legacyEduStarsKey), isFalse);
      expect(prefs.containsKey(ChildStorage.legacyEduMosqueKey), isFalse);
      expect(prefs.containsKey(ChildStorage.legacyEduLettersKey), isFalse);

      // A sibling added later does not inherit it.
      final kids = c.read(childrenProvider.notifier);
      kids.add('Maryam', ChildAvatar.flower, maxChildren: 5);
      kids.select(c.read(childrenProvider).children.last.id);
      expect(c.read(starsProvider), 0);
      expect(c.read(mosqueProvider), 0);
      expect(c.read(lettersProgressProvider), isEmpty);
    });

    test('goes to the active child on a device with several children', () async {
      final (c, prefs) = await makeContainer({
        ChildStorage.childrenKey: '[{"id":"child-1","nickname":"A"},{"id":"kid-b","nickname":"B"}]',
        ChildStorage.activeKey: 'kid-b',
        ChildStorage.legacyEduStarsKey: 9,
      });
      expect(c.read(activeChildIdProvider), 'kid-b');
      expect(c.read(starsProvider), 9);
      expect(prefs.getInt(ChildStorage.eduStarsKey('kid-b')), 9);
      expect(prefs.containsKey(ChildStorage.eduStarsKey('child-1')), isFalse);
    });

    test('is idempotent and never overwrites a child\'s own progress', () async {
      SharedPreferences.setMockInitialValues({
        ChildStorage.legacyEduStarsKey: 7,
        ChildStorage.eduStarsKey('child-1'): 2,
      });
      final prefs = await SharedPreferences.getInstance();
      ChildStorage.migrateEdu(prefs, 'child-1');
      ChildStorage.migrateEdu(prefs, 'child-1');
      expect(prefs.getInt(ChildStorage.eduStarsKey('child-1')), 2);
      expect(prefs.containsKey(ChildStorage.legacyEduStarsKey), isFalse);

      // Nothing left to migrate for a second child.
      ChildStorage.migrateEdu(prefs, 'kid-b');
      expect(prefs.containsKey(ChildStorage.eduStarsKey('kid-b')), isFalse);
    });

    test('corrupted old values are still clamped after moving', () async {
      final (c, _) = await makeContainer({StarsController.prefsKey: -7, MosqueController.prefsKey: 99});
      expect(c.read(starsProvider), 0);
      expect(c.read(mosqueProvider), greaterThan(0));
    });
  });
}
