import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/child_profile.dart';
import '../../data/models/plan.dart';
import '../../features/prayer/prayer_providers.dart';
import '../../features/settings/settings_controller.dart';
import '../billing/subscription_service.dart';
import 'child_pause.dart';
import 'child_storage.dart';
import 'family_repository.dart';

@immutable
class ChildrenState {
  const ChildrenState({required this.children, required this.activeId, this.boundChildId, this.freeChildId});

  final List<ChildProfile> children;

  /// The child whose wallet and tasks this device is showing right now.
  final String activeId;

  /// Set on a paired child's device: it is bound to this child and cannot switch.
  final String? boundChildId;

  /// The child the parent chose to keep active on the Free plan (null = the first child).
  /// See [ChildPause] / docs/decisions/FREE-ONE-CHILD.md.
  final String? freeChildId;

  bool get isBound => boundChildId != null;

  ChildProfile get active => children.firstWhere((c) => c.id == activeId, orElse: () => children.first);

  ChildProfile? byId(String id) => children.where((c) => c.id == id).firstOrNull;
}

enum AddChildResult { added, limitReached, invalidName, notAllowed }

/// Child profiles on this device. Parent devices can add, rename, remove and
/// switch children; a paired child device is bound to a single child.
class ChildrenController extends Notifier<ChildrenState> {
  @override
  ChildrenState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final children = ChildStorage.migrate(prefs);
    final boundRaw = prefs.getString(ChildStorage.boundKey);
    final bound = boundRaw != null && children.any((c) => c.id == boundRaw) ? boundRaw : null;
    final savedActive = prefs.getString(ChildStorage.activeKey);
    final active = bound ??
        (savedActive != null && children.any((c) => c.id == savedActive) ? savedActive : children.first.id);
    final freeRaw = prefs.getString(ChildStorage.freeChildKey);
    final free = freeRaw != null && children.any((c) => c.id == freeRaw) ? freeRaw : null;
    return ChildrenState(children: children, activeId: active, boundChildId: bound, freeChildId: free);
  }

  /// Adds a child if the plan allows it ([maxChildren] from `Entitlement.limits`).
  AddChildResult add(String nickname, ChildAvatar avatar, {required int maxChildren, FormOfAddress? address}) {
    if (state.isBound) return AddChildResult.notAllowed;
    if (!canAddChild(currentCount: state.children.length, maxChildren: maxChildren)) {
      return AddChildResult.limitReached;
    }
    final name = ChildProfile.cleanNickname(nickname);
    if (name == null) return AddChildResult.invalidName;
    var id = ChildProfile.newId();
    while (state.children.any((c) => c.id == id)) {
      id = ChildProfile.newId();
    }
    final child = ChildProfile(id: id, nickname: name, avatar: avatar, address: address);
    _save(ChildrenState(
      children: [...state.children, child],
      activeId: state.activeId,
      boundChildId: state.boundChildId,
      freeChildId: state.freeChildId,
    ));
    _sync(child);
    return AddChildResult.added;
  }

  /// Returns false when the nickname is invalid or the child is unknown.
  /// [address] null keeps the current form of address unless [clearAddress] is true.
  bool edit(
    String childId, {
    required String nickname,
    required ChildAvatar avatar,
    FormOfAddress? address,
    bool clearAddress = false,
  }) {
    if (state.isBound) return false;
    final name = ChildProfile.cleanNickname(nickname);
    final current = state.byId(childId);
    if (name == null || current == null) return false;
    final updated = current.copyWith(nickname: name, avatar: avatar, address: address, clearAddress: clearAddress);
    _save(ChildrenState(
      children: [for (final c in state.children) c.id == childId ? updated : c],
      activeId: state.activeId,
      boundChildId: state.boundChildId,
      freeChildId: state.freeChildId,
    ));
    _sync(updated);
    return true;
  }

  /// Removes a child and all of its data. The last child cannot be removed.
  bool remove(String childId) {
    if (state.isBound || state.children.length <= 1 || state.byId(childId) == null) return false;
    final rest = state.children.where((c) => c.id != childId).toList();
    final active = state.activeId == childId ? rest.first.id : state.activeId;
    ChildStorage.deleteChildData(ref.read(sharedPrefsProvider), childId);
    final free = state.freeChildId == childId ? null : state.freeChildId;
    _save(ChildrenState(children: rest, activeId: active, boundChildId: null, freeChildId: free));
    ref.read(familyRepositoryProvider).deleteChild(childId).catchError((Object e) {
      debugPrint('child delete sync failed: $e');
    });
    syncFreeChild();
    return true;
  }

  /// Parent device only: show another child's wallet and tasks. A child paused on the Free
  /// plan cannot be selected (returns false).
  bool select(String childId) {
    if (state.isBound || state.byId(childId) == null) return false;
    // Same rule as [childPauseProvider], computed here: a notifier may not read a provider
    // that depends on itself (Riverpod CircularDependencyError).
    final multiple = hasFeature(ref.read(planEntitlementProvider), AppFeature.multipleChildren);
    final pause = childPauseFor(
      children: state.children,
      multipleChildrenAllowed: multiple,
      chosenFreeChildId: state.freeChildId,
    );
    if (pause.isPaused(childId)) return false;
    if (state.activeId == childId) return true;
    _save(ChildrenState(children: state.children, activeId: childId, boundChildId: null, freeChildId: state.freeChildId));
    return true;
  }

  /// Parent device only, after the parent PIN: the child that stays active on the Free plan.
  /// Nothing is deleted; the other children are paused until the family subscribes.
  bool chooseFreeChild(String childId) {
    if (state.isBound || state.byId(childId) == null) return false;
    _save(ChildrenState(children: state.children, activeId: childId, boundChildId: null, freeChildId: childId));
    syncFreeChild();
    return true;
  }

  /// Tells the server which child stays active on Free, only when it differs from what the
  /// server already has (the server's default is `child-1`). At most one call per change.
  void syncFreeChild() {
    if (state.isBound) return;
    final prefs = ref.read(sharedPrefsProvider);
    final free = freeChildIdOf(state.children, state.freeChildId);
    final synced = prefs.getString(ChildStorage.freeChildSyncedKey) ?? ChildProfile.defaultId;
    if (free == synced) return;
    ref.read(familyRepositoryProvider).setFreeChild(free).then((stored) {
      if (stored) prefs.setString(ChildStorage.freeChildSyncedKey, free);
    }).catchError((Object e) {
      debugPrint('free child sync failed: $e');
    });
  }

  /// Called after this device was paired to [child]: from now on it shows only that child.
  void bindTo(ChildProfile child) {
    final others = state.children.where((c) => c.id != child.id);
    _save(ChildrenState(children: [child, ...others], activeId: child.id, boundChildId: child.id, freeChildId: state.freeChildId));
  }

  void _save(ChildrenState next) {
    final prefs = ref.read(sharedPrefsProvider);
    ChildStorage.writeChildren(prefs, next.children);
    prefs.setString(ChildStorage.activeKey, next.activeId);
    if (next.boundChildId != null) {
      prefs.setString(ChildStorage.boundKey, next.boundChildId!);
    } else {
      prefs.remove(ChildStorage.boundKey);
    }
    if (next.freeChildId != null) {
      prefs.setString(ChildStorage.freeChildKey, next.freeChildId!);
    } else {
      prefs.remove(ChildStorage.freeChildKey);
    }
    state = next;
  }

  void _sync(ChildProfile child) {
    ref.read(familyRepositoryProvider).saveChild(child).catchError((Object e) {
      debugPrint('child sync failed: $e');
    });
  }
}

final childrenProvider = NotifierProvider<ChildrenController, ChildrenState>(ChildrenController.new);

/// Server-written plan fields of the family, for paired child devices. The last value is
/// cached so a child device that starts offline keeps the same answer. Until anything is
/// known the child is NOT paused, so its device stays locked (the safe default).
final familyPlanStatusProvider = StreamProvider<FamilyPlanStatus?>((ref) async* {
  final prefs = ref.watch(sharedPrefsProvider);
  yield FamilyPlanStatus.tryDecode(prefs.getString(ChildStorage.familyStatusKey));
  await for (final status in ref.watch(familyRepositoryProvider).watchFamilyStatus()) {
    await prefs.setString(ChildStorage.familyStatusKey, status.encode());
    yield status;
  }
});

/// Which children are paused on the Free plan (owner decision 2026-11-21).
/// * Parent / shared device: from this device's plan (paid, cached, store or device trial).
/// * Paired child device: from the family's server-written plan ([familyPlanStatusProvider]).
final childPauseProvider = Provider<ChildPause>((ref) {
  final children = ref.watch(childrenProvider);
  final bound = children.boundChildId;
  if (bound != null) {
    ref.watch(clockProvider); // the server-side trial ends on time
    final status = ref.watch(familyPlanStatusProvider).valueOrNull;
    final paused = status != null && status.childPaused(bound, DateTime.now().toUtc());
    return ChildPause(
      freeChildId: status?.freeChildId ?? ChildProfile.defaultId,
      pausedIds: paused ? {bound} : const {},
    );
  }
  final multiple = ref.watch(planEntitlementProvider.select((e) => hasFeature(e, AppFeature.multipleChildren)));
  return childPauseFor(
    children: children.children,
    multipleChildrenAllowed: multiple,
    chosenFreeChildId: children.freeChildId,
  );
});

/// True on a paired child device whose child is paused: the device shows the friendly
/// "ask a parent" screen and is not locked or monitored as a separate child.
final thisDevicePausedProvider = Provider<bool>((ref) {
  final bound = ref.watch(childrenProvider.select((s) => s.boundChildId));
  return bound != null && ref.watch(childPauseProvider).isPaused(bound);
});

/// The child whose wallet this device shows. Fixed on a paired child device; switchable from
/// the parent dashboard otherwise. A child paused on Free is never shown: the free child is.
final activeChildIdProvider = Provider<String>((ref) {
  final bound = ref.watch(childrenProvider.select((s) => s.boundChildId));
  if (bound != null) return bound;
  final selected = ref.watch(childrenProvider.select((s) => s.activeId));
  return effectiveActiveChildId(selected: selected, pause: ref.watch(childPauseProvider));
});
