import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/child_profile.dart';
import '../../features/settings/settings_controller.dart';
import '../billing/entitlement_cache.dart';
import 'approval_queue.dart';
import 'child_storage.dart';
import 'children_controller.dart';
import 'family_bootstrap.dart';
import 'family_repository.dart';
import 'firestore_family_repository.dart';

/// "This device was removed from the family" (BACKLOG P1-3a).
///
/// When a parent removes a linked device (`removeLinkedDevice`, P1-3), the server takes its uid out
/// of `members` and revokes its tokens. The removed device then only sees permission-denied from
/// Firestore. This file turns that into a calm "ask a parent" screen and a safe reset:
///
/// * **Detection.** A permission-denied on the live family-doc listener is only a HINT (a rules
///   mistake could cause it too). The device is treated as removed only when the server says so
///   explicitly: the `checkDeviceMembership` callable answers `{member: false}` for this device's
///   own uid, twice in a row ([RemovalDetector]). Offline, timeouts, errors or a function that is
///   not deployed are "unknown" and never count (offline-first: no blocking error for the child).
/// * **Child safety.** The removed state is saved before anything else and forces a LOCKED policy
///   (`removedLockPolicy` in app_lock_service.dart), on every plan, until a parent enters the
///   parent PIN on this device ([DeviceRemovalController.parentSetUpAgain]). Clearing the old
///   family's data can therefore never unlock games.
/// * **No leak.** The old family's cached data on this device is deleted: child nicknames and
///   avatars, wallets, tasks, learning progress, the cached family plan, queued approvals, the
///   family id; the Firebase session is signed out and the Firestore offline cache is cleared at
///   the next start (Firestore only allows that before it is used).

/// What the server said about this device's membership.
enum MembershipProbe { member, notMember, unknown }

/// The `checkDeviceMembership` answer: only an explicit boolean counts, anything else is unknown.
MembershipProbe membershipFromServer(Object? data) {
  if (data is Map) {
    final member = data['member'];
    if (member == true) return MembershipProbe.member;
    if (member == false) return MembershipProbe.notMember;
  }
  return MembershipProbe.unknown;
}

bool isPermissionDenied(Object error) => error is FirebaseException && error.code == 'permission-denied';

/// The synced family's membership signals ([FirestoreFamilyRepository] implements it).
abstract class MembershipSource {
  /// Emits when a live listener on the family doc is refused (permission-denied). A hint only.
  Stream<void> accessDenied();

  /// Asks the server whether this device is still a member. Never throws.
  Future<MembershipProbe> probe();
}

/// Pure decision (unit-tested): removed only after [confirmations] explicit "not a member"
/// answers in a row, [delay] apart. A member or unknown (offline) answer stops at once.
class RemovalDetector {
  const RemovalDetector({this.confirmations = 2, this.delay = const Duration(seconds: 3)});

  final int confirmations;
  final Duration delay;

  Future<bool> isRemoved(Future<MembershipProbe> Function() probe) async {
    for (var i = 0; i < confirmations; i++) {
      if (i > 0 && delay > Duration.zero) await Future<void>.delayed(delay);
      if (await probe() != MembershipProbe.notMember) return false;
    }
    return true;
  }
}

/// Storage keys and the data reset (pure prefs work, unit-tested).
abstract final class DeviceRemoval {
  /// Set when the server confirmed the removal; cleared only after the parent PIN.
  static const removedKey = 'family.removedFromFamily';

  /// The Firestore offline cache still holds the old family's docs: cleared at the next start.
  static const clearCacheKey = 'family.clearCachePending';

  /// Deletes everything this device cached about the old family. Device settings (language, city,
  /// lock mode, the parent PIN) stay: they keep the device locked and belong to the device.
  static Future<void> clearFamilyData(SharedPreferences prefs) async {
    final children = ChildStorage.readChildren(prefs) ?? const <ChildProfile>[];
    for (final id in {ChildProfile.defaultId, ...children.map((c) => c.id)}) {
      ChildStorage.deleteChildData(prefs, id);
    }
    for (final key in const [
      ChildStorage.childrenKey,
      ChildStorage.activeKey,
      ChildStorage.boundKey,
      ChildStorage.freeChildKey,
      ChildStorage.freeChildSyncedKey,
      ChildStorage.familyStatusKey,
      ChildStorage.legacyWalletKey,
      ChildStorage.legacyTasksKey,
      ChildStorage.legacyAdhkarKey,
      ChildStorage.legacyEduStarsKey,
      ChildStorage.legacyEduMosqueKey,
      ChildStorage.legacyEduLettersKey,
      ApprovalQueue.storageKey,
      FamilyBootstrap.idKey,
      FamilyBootstrap.pendingKey,
    ]) {
      await prefs.remove(key);
    }
    await prefs.setBool(clearCacheKey, true);
  }

  /// Start-up, before Firestore is used: clears its offline cache after a removal.
  static Future<void> clearFirestoreCacheIfPending(SharedPreferences prefs, {required Duration timeout}) async {
    if (prefs.getBool(clearCacheKey) != true) return;
    try {
      await FirebaseFirestore.instance.clearPersistence().timeout(timeout);
      await prefs.remove(clearCacheKey);
    } catch (e) {
      debugPrint('Firestore cache not cleared yet, retrying next start: $e');
    }
  }
}

/// The membership signals of this device's family, or null for a local-only family.
final membershipSourceProvider = Provider<MembershipSource?>((ref) {
  final repo = ref.watch(familyRepositoryProvider);
  if (repo case final MembershipSource source) return source;
  return null;
});

/// Time between the two server answers ([RemovalDetector.delay]); tests use zero.
final removalConfirmDelayProvider = Provider<Duration>((_) => const Duration(seconds: 3));

/// How long the watcher waits before listening again after a hint that was not a removal.
final removalRelistenDelayProvider = Provider<Duration>((_) => const Duration(minutes: 5));

/// Firebase session steps of the reset (no-ops without Firebase; tests override them).
class RemovalSession {
  const RemovalSession({required this.signOut, required this.startFreshFamily});

  /// Ends the removed (revoked) anonymous session.
  final Future<void> Function() signOut;

  /// After the parent PIN: a new anonymous session and a fresh family with this device as its only
  /// member ([FamilyBootstrap]). Returns its id, or null to stay local this session (offline).
  final Future<String?> Function(SharedPreferences prefs) startFreshFamily;
}

final removalSessionProvider = Provider<RemovalSession>((ref) {
  if (!ref.watch(firebaseReadyProvider)) {
    return RemovalSession(signOut: () async {}, startFreshFamily: (_) async => null);
  }
  return RemovalSession(
    signOut: () => FirebaseAuth.instance.signOut(),
    startFreshFamily: (prefs) => FamilyBootstrap.run(
      prefs,
      newId: FirestoreFamilyRepository.newFamilyId,
      signIn: FirestoreFamilyRepository.signIn,
      create: FirestoreFamilyRepository.createFamily,
    ),
  );
});

/// True while this device is "removed from the family": the app shows only the removed screen and
/// games stay locked. Persisted, so restarting the app keeps it.
class DeviceRemovalController extends Notifier<bool> {
  bool _checking = false;

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(DeviceRemoval.removedKey) ?? false;

  /// Asks the server ([RemovalDetector]); resets the device when it confirms the removal.
  /// Returns true when the device is (now) removed.
  Future<bool> check() async {
    if (state || _checking) return state;
    final source = ref.read(membershipSourceProvider);
    final familyId = ref.read(familyIdProvider);
    if (source == null || familyId == null) return false;
    _checking = true;
    try {
      final removed = await RemovalDetector(delay: ref.read(removalConfirmDelayProvider)).isRemoved(source.probe);
      // Paired to another family meanwhile: the answer was about the old one.
      if (!removed || ref.read(familyIdProvider) != familyId) return false;
      await markRemoved();
      return true;
    } finally {
      _checking = false;
    }
  }

  /// The server confirmed the removal: lock first, then forget the old family.
  @visibleForTesting
  Future<void> markRemoved() async {
    final prefs = ref.read(sharedPrefsProvider);
    await prefs.setBool(DeviceRemoval.removedKey, true);
    state = true; // lockPolicyProvider switches to the locked "removed" policy right away
    await DeviceRemoval.clearFamilyData(prefs);
    try {
      await ref.read(entitlementCacheProvider).recordVerified(null); // the old family's plan
    } catch (e) {
      debugPrint('plan cache not cleared: $e');
    }
    ref.invalidate(childrenProvider); // a fresh default child without a name
    ref.read(familyIdProvider.notifier).state = null; // local family: no more server calls
    try {
      await ref.read(removalSessionProvider).signOut();
    } catch (e) {
      debugPrint('sign-out after removal failed: $e');
    }
  }

  /// Only after the parent PIN on this device: leaves the removed state. The device is a fresh,
  /// unlinked family (synced when online); the parent links it again from the Parent area.
  Future<void> parentSetUpAgain() async {
    if (!state) return;
    final prefs = ref.read(sharedPrefsProvider);
    String? freshId;
    try {
      freshId = await ref.read(removalSessionProvider).startFreshFamily(prefs);
    } catch (e) {
      debugPrint('fresh family not created, local for now: $e');
    }
    await prefs.remove(DeviceRemoval.removedKey);
    ref.read(familyIdProvider.notifier).state = freshId;
    state = false;
  }
}

final deviceRemovalProvider = NotifierProvider<DeviceRemovalController, bool>(DeviceRemovalController.new);

/// Keep alive from the app root: listens for the permission-denied hint on the family doc and
/// lets [DeviceRemovalController.check] ask the server. Nothing runs for a local-only family.
final deviceRemovalWatcherProvider = Provider<void>((ref) {
  if (ref.watch(deviceRemovalProvider)) return;
  final source = ref.watch(membershipSourceProvider);
  if (source == null) return;
  final relistenDelay = ref.read(removalRelistenDelayProvider);
  StreamSubscription<void>? sub;
  Timer? relisten;
  var disposed = false;

  void listen() {
    if (disposed) return;
    sub?.cancel();
    sub = source.accessDenied().listen(
      (_) async {
        await sub?.cancel();
        sub = null;
        if (disposed) return;
        final removed = await ref.read(deviceRemovalProvider.notifier).check();
        if (!removed && !disposed) {
          relisten?.cancel();
          relisten = Timer(relistenDelay, listen);
        }
      },
      onError: (Object _) {},
      // Firestore ends a listener after an error: listen again later.
      onDone: () {
        if (disposed || sub == null) return;
        relisten?.cancel();
        relisten = Timer(relistenDelay, listen);
      },
    );
  }

  listen();
  ref.onDispose(() {
    disposed = true;
    sub?.cancel();
    relisten?.cancel();
  });
});
