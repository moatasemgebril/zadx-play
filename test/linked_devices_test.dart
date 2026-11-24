// BACKLOG P1-3: a parent removes a linked phone (child device or another parent phone) from the
// family. The server (`removeLinkedDevice`) decides; the app lists the devices, asks for
// confirmation and shows a friendly message for every outcome, never a crash.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/data/models/child_profile.dart';
import 'package:zadx/features/parent/linked_devices_list.dart';
import 'package:zadx/features/settings/settings_controller.dart';
import 'package:zadx/l10n/app_localizations.dart';
import 'package:zadx/services/family/child_storage.dart';
import 'package:zadx/services/family/family_repository.dart';

class _DevicesRepo extends LocalFamilyRepository {
  _DevicesRepo(this.devices);
  final List<LinkedDevice> devices;
  final removed = <String>[];
  Object? failWith;

  @override
  Stream<List<LinkedDevice>> watchLinkedDevices() => Stream.value(devices);

  @override
  Future<void> removeLinkedDevice(String deviceUid) async {
    if (failWith != null) throw failWith!;
    removed.add(deviceUid);
  }
}

const _me = LinkedDevice(uid: 'parentUid0001', isThisDevice: true);
const _otherParent = LinkedDevice(uid: 'parentPhone2X9');
const _kid = LinkedDevice(uid: 'kidDeviceAB12', childId: ChildProfile.defaultId);

Future<_DevicesRepo> _pump(
  WidgetTester tester, {
  String lang = 'en',
  List<LinkedDevice> devices = const [_me, _otherParent, _kid],
  bool childDevice = false,
}) async {
  SharedPreferences.setMockInitialValues({
    if (childDevice) ChildStorage.boundKey: ChildProfile.defaultId,
  });
  final prefs = await SharedPreferences.getInstance();
  final repo = _DevicesRepo(devices);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      familyRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp(
      locale: Locale(lang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: SingleChildScrollView(child: LinkedDevicesList())),
    ),
  ));
  await tester.pumpAndSettle();
  return repo;
}

Finder _removeButton(LinkedDevice d) => find.byKey(ValueKey('removeDevice-${d.uid}'));

Future<void> _removeAndConfirm(WidgetTester tester, LinkedDevice device, {required String confirm}) async {
  await tester.tap(_removeButton(device));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, confirm));
  await tester.pumpAndSettle();
}

void main() {
  group('parseLinkedDevices', () {
    test('role from childDevices, this phone first, duplicates and junk skipped', () {
      final list = parseLinkedDevices({
        'members': ['kid1', 'p2', 'me', 'kid1', 42, ''],
        'childDevices': {'kid1': 'c1', 'p2': null},
      }, 'me');
      expect(list.map((d) => d.uid), ['me', 'p2', 'kid1']);
      expect(list[0].isThisDevice, isTrue);
      expect(list[1].isParent, isTrue);
      expect(list[2].childId, 'c1');
      expect(list[2].isParent, isFalse);
    });

    test('malformed family doc: no devices', () {
      expect(parseLinkedDevices({}, 'me'), isEmpty);
      expect(parseLinkedDevices({'members': 'me'}, 'me'), isEmpty);
    });

    test('local-only family: no devices, removal is refused (never a silent success)', () async {
      final local = LocalFamilyRepository();
      expect(await local.watchLinkedDevices().toList(), isEmpty);
      await expectLater(local.removeLinkedDevice('x'), throwsA(isA<DeviceRemovalRejected>()));
    });
  });

  testWidgets('lists linked phones; this phone cannot be removed from here', (tester) async {
    await _pump(tester);
    expect(find.text('Linked devices'), findsOneWidget);
    expect(find.textContaining('This phone (you)'), findsOneWidget);
    expect(find.textContaining('Parent phone'), findsOneWidget);
    expect(find.textContaining("My child's device"), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Remove device'), findsNWidgets(2));
    expect(_removeButton(_me), findsNothing);
    expect(_removeButton(_otherParent), findsOneWidget);
    expect(_removeButton(_kid), findsOneWidget);
  });

  testWidgets('cancel keeps the device; confirm removes the child device', (tester) async {
    final repo = await _pump(tester);
    await tester.tap(_removeButton(_kid));
    await tester.pumpAndSettle();
    expect(find.text('Remove this device?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.removed, isEmpty);

    await _removeAndConfirm(tester, _kid, confirm: 'Remove');
    expect(repo.removed, ['kidDeviceAB12']);
    expect(find.text('Device removed'), findsOneWidget);
  });

  testWidgets('removes another parent phone', (tester) async {
    final repo = await _pump(tester);
    await _removeAndConfirm(tester, _otherParent, confirm: 'Remove');
    expect(repo.removed, ['parentPhone2X9']);
  });

  testWidgets('last parent refused by the server: friendly message', (tester) async {
    final repo = await _pump(tester);
    repo.failWith = const DeviceRemovalRejected('last_parent');
    await _removeAndConfirm(tester, _otherParent, confirm: 'Remove');
    expect(find.text("You can't remove the family's last parent phone."), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('any other failure (offline, unexpected error): friendly message, no crash', (tester) async {
    final repo = await _pump(tester);
    for (final error in [const DeviceRemovalRejected('unavailable'), StateError('boom')]) {
      repo.failWith = error;
      await _removeAndConfirm(tester, _kid, confirm: 'Remove');
      expect(find.text("Couldn't remove the device right now. Please try again soon."), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    expect(repo.removed, isEmpty);
  });

  testWidgets('Arabic first: the dialog asks in Arabic and removes on confirm', (tester) async {
    final repo = await _pump(tester, lang: 'ar');
    expect(find.text('الأجهزة المربوطة'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'إزالة الجهاز'), findsNWidgets(2));
    expect(find.textContaining('موبايل ولي أمر'), findsOneWidget);
    expect(find.textContaining('جهاز طفلي'), findsOneWidget);
    await tester.tap(_removeButton(_otherParent));
    await tester.pumpAndSettle();
    expect(find.text('إزالة الجهاز ده؟'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'إزالة'));
    await tester.pumpAndSettle();
    expect(repo.removed, ['parentPhone2X9']);
    expect(find.text('تمت إزالة الجهاز'), findsOneWidget);
  });

  testWidgets('a paired child device sees no device management', (tester) async {
    await _pump(tester, childDevice: true);
    expect(find.text('Linked devices'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('only this phone linked: nothing to manage', (tester) async {
    await _pump(tester, devices: const [_me]);
    expect(find.text('Linked devices'), findsNothing);
  });
}
