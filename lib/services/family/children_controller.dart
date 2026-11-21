import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/child_profile.dart';
import '../../features/settings/settings_controller.dart';
import 'child_storage.dart';
import 'family_repository.dart';

@immutable
class ChildrenState {
  const ChildrenState({required this.children, required this.activeId, this.boundChildId});

  final List<ChildProfile> children;

  /// The child whose wallet and tasks this device is showing right now.
  final String activeId;

  /// Set on a paired child's device: it is bound to this child and cannot switch.
  final String? boundChildId;

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
    return ChildrenState(children: children, activeId: active, boundChildId: bound);
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
    _save(ChildrenState(children: [...state.children, child], activeId: state.activeId, boundChildId: state.boundChildId));
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
    _save(ChildrenState(children: rest, activeId: active, boundChildId: null));
    ref.read(familyRepositoryProvider).deleteChild(childId).catchError((Object e) {
      debugPrint('child delete sync failed: $e');
    });
    return true;
  }

  /// Parent device only: show another child's wallet and tasks.
  void select(String childId) {
    if (state.isBound || state.byId(childId) == null || state.activeId == childId) return;
    _save(ChildrenState(children: state.children, activeId: childId, boundChildId: null));
  }

  /// Called after this device was paired to [child]: from now on it shows only that child.
  void bindTo(ChildProfile child) {
    final others = state.children.where((c) => c.id != child.id);
    _save(ChildrenState(children: [child, ...others], activeId: child.id, boundChildId: child.id));
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
    state = next;
  }

  void _sync(ChildProfile child) {
    ref.read(familyRepositoryProvider).saveChild(child).catchError((Object e) {
      debugPrint('child sync failed: $e');
    });
  }
}

final childrenProvider = NotifierProvider<ChildrenController, ChildrenState>(ChildrenController.new);

/// The child whose wallet this device shows. Fixed on a paired child device;
/// switchable from the parent dashboard otherwise.
final activeChildIdProvider = Provider<String>((ref) => ref.watch(childrenProvider.select((s) => s.activeId)));
