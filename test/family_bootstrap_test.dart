import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zadx/services/family/family_bootstrap.dart';

// Quality Gate on #33: `ensureFamily(...).timeout(5s)` could create orphan families (the write
// landed after the timeout, the id was forgotten, the next start created another family).
// FamilyBootstrap saves the id locally first and retries the SAME id with an idempotent create.

const _timeout = Duration(milliseconds: 50);

class _Backend {
  final created = <String>[]; // every create call, in order
  final docs = <String, Set<String>>{}; // familyId -> members (what the server ends up with)
  bool hang = false; // create never answers (slow network) but the write still lands later
  bool offline = false; // sign-in fails
  var ids = 0;

  String newId() => 'fam${++ids}';

  Future<String> signIn() async {
    if (offline) throw Exception('offline');
    return 'uid1';
  }

  Future<void> create(String familyId, String uid) {
    created.add(familyId);
    (docs[familyId] ??= <String>{}).add(uid); // idempotent: arrayUnion
    return hang ? Completer<void>().future : Future.value();
  }

  Future<String?> start(SharedPreferences prefs) =>
      FamilyBootstrap.run(prefs, newId: newId, signIn: signIn, create: create, timeout: _timeout);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first launch online: id saved, family created once, marker cleared', () async {
    final prefs = await SharedPreferences.getInstance();
    final b = _Backend();
    expect(await b.start(prefs), 'fam1');
    expect(prefs.getString(FamilyBootstrap.idKey), 'fam1');
    expect(prefs.getString(FamilyBootstrap.pendingKey), isNull);
    expect(b.created, ['fam1']);

    // Later starts reuse the id and do not write the family again.
    expect(await b.start(prefs), 'fam1');
    expect(b.created, ['fam1']);
  });

  test('a timed-out create never leaves an orphan family: the next start retries the SAME id', () async {
    final prefs = await SharedPreferences.getInstance();
    final b = _Backend()..hang = true;

    // Slow network: the write lands on the server, but the app gives up after the timeout.
    expect(await b.start(prefs), isNull, reason: 'local mode this session');
    expect(prefs.getString(FamilyBootstrap.idKey), 'fam1', reason: 'id saved before the write');
    expect(prefs.getString(FamilyBootstrap.pendingKey), 'fam1');

    // Still slow on the next start: same id again, no second family.
    expect(await b.start(prefs), isNull);

    // Network is back.
    b.hang = false;
    expect(await b.start(prefs), 'fam1');
    expect(prefs.getString(FamilyBootstrap.pendingKey), isNull);

    expect(b.created.toSet(), {'fam1'}, reason: 'only one family id was ever written');
    expect(b.docs, {'fam1': {'uid1'}}, reason: 'retries are idempotent');
    expect(b.ids, 1, reason: 'a new id is generated only once');
  });

  test('offline first launch: id kept for the next start, nothing written', () async {
    final prefs = await SharedPreferences.getInstance();
    final b = _Backend()..offline = true;
    expect(await b.start(prefs), isNull);
    expect(b.created, isEmpty);
    expect(prefs.getString(FamilyBootstrap.idKey), 'fam1');

    b.offline = false;
    expect(await b.start(prefs), 'fam1');
    expect(b.created, ['fam1']);
    expect(b.ids, 1);
  });

  test('an existing family is not written again', () async {
    SharedPreferences.setMockInitialValues({FamilyBootstrap.idKey: 'existing'});
    final prefs = await SharedPreferences.getInstance();
    final b = _Backend();
    expect(await b.start(prefs), 'existing');
    expect(b.created, isEmpty);
    expect(b.ids, 0);
  });

  test('a device paired into another family drops its own pending create', () async {
    // Pairing (pairing_service.dart) replaced family.id before the device's own family was written.
    SharedPreferences.setMockInitialValues({
      FamilyBootstrap.idKey: 'parentFamily',
      FamilyBootstrap.pendingKey: 'fam1',
    });
    final prefs = await SharedPreferences.getInstance();
    final b = _Backend();
    expect(await b.start(prefs), 'parentFamily');
    expect(b.created, isEmpty, reason: 'never re-creates or joins a family by itself');
    expect(prefs.getString(FamilyBootstrap.pendingKey), isNull);
  });
}
