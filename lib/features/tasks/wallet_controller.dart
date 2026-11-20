import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog/default_tasks.dart';
import '../../data/models/family_task.dart';
import '../../services/family/family_repository.dart';
import '../prayer/prayer_calculator.dart';
import '../prayer/prayer_providers.dart';
import '../settings/settings_controller.dart';

/// The child's day: tasks, earned/used minutes and the prayer lock.
@immutable
class WalletState {
  const WalletState({
    required this.day,
    required this.tasks,
    required this.progress,
    this.usedMinutes = 0,
    this.prayerLock = false,
    this.lockedPrayer,
  });

  final String day;
  final List<TaskDefinition> tasks;
  final Map<String, TaskProgress> progress;
  final int usedMinutes;
  final bool prayerLock;
  final Prayer? lockedPrayer;

  TaskProgress progressOf(String id) => progress[id] ?? const TaskProgress();

  bool get requiredDone =>
      tasks.where((t) => t.required).every((t) => progressOf(t.id).status == TaskStatus.done);

  int get earnedMinutes => tasks
      .where((t) => progressOf(t.id).status == TaskStatus.done)
      .fold(0, (sum, t) => sum + t.rewardMinutes);

  int get remainingMinutes => (earnedMinutes - usedMinutes).clamp(0, 1 << 30);

  /// Device games are playable only when all three conditions hold.
  bool get gamesUnlocked => requiredDone && !prayerLock && remainingMinutes > 0;

  int get doneCount => tasks.where((t) => progressOf(t.id).status == TaskStatus.done).length;

  List<TaskDefinition> get pending =>
      tasks.where((t) => progressOf(t.id).status == TaskStatus.pending).toList();

  LockReason? get lockReason {
    if (prayerLock) return LockReason.prayer;
    if (!requiredDone) return LockReason.requiredTasks;
    if (remainingMinutes <= 0) return LockReason.noTime;
    return null;
  }

  WalletState copyWith({
    String? day,
    List<TaskDefinition>? tasks,
    Map<String, TaskProgress>? progress,
    int? usedMinutes,
    bool? prayerLock,
    Prayer? lockedPrayer,
    bool clearLockedPrayer = false,
  }) =>
      WalletState(
        day: day ?? this.day,
        tasks: tasks ?? this.tasks,
        progress: progress ?? this.progress,
        usedMinutes: usedMinutes ?? this.usedMinutes,
        prayerLock: prayerLock ?? this.prayerLock,
        lockedPrayer: clearLockedPrayer ? null : (lockedPrayer ?? this.lockedPrayer),
      );

  FamilyDay toFamilyDay() => FamilyDay(
        day: day,
        progress: progress.map((k, v) => MapEntry(k, v.toJson())),
        usedMinutes: usedMinutes,
        prayerLock: prayerLock,
        earnedMinutes: earnedMinutes,
        requiredDone: requiredDone,
      );
}

enum LockReason { prayer, requiredTasks, noTime }

/// Business rules for tasks and play time. UI and native lock code only *read*
/// [WalletState]; every change goes through this controller.
class WalletController extends Notifier<WalletState> {
  static const _storageKey = 'wallet.state';
  StreamSubscription<FamilyDay>? _remoteSub;

  FamilyRepository get _repo => ref.read(familyRepositoryProvider);
  String get _childId => ref.read(activeChildIdProvider);

  @override
  WalletState build() {
    // Rebuild only when the date changes (not every minute).
    final today = ref.watch(cityNowProvider.select((n) => _dayKey(n.local)));
    final restored = _restore(today);

    // Re-subscribes automatically when the device is paired to another family.
    final repo = ref.watch(familyRepositoryProvider);
    _remoteSub?.cancel();
    _remoteSub = repo.watchDay(_childId, today).listen(_applyRemote);
    ref.onDispose(() => _remoteSub?.cancel());

    // Lock games automatically when a new prayer time starts.
    ref.listen<Prayer>(nextPrayerProvider, (previous, next) {
      if (previous != null && previous != next && ref.read(settingsProvider).lockAtAdhan) {
        startPrayerLock(previous);
      }
    });

    return restored;
  }

  // ---- child actions -------------------------------------------------------

  /// Child marks a task as done → waits for parent approval.
  void submit(String taskId) => _setStatus(taskId, TaskStatus.pending, notifyType: 'task_submitted');

  /// Exercise counter: +1 rep; reaching the target submits the task.
  void addRep(String taskId) {
    final def = state.tasks.firstWhere((t) => t.id == taskId);
    final p = state.progressOf(taskId);
    if (p.status != TaskStatus.todo || def.reps == null) return;
    final count = p.count + 1;
    if (count >= def.reps!) {
      _update(state.copyWith(progress: {...state.progress, taskId: p.copyWith(count: def.reps)}));
      submit(taskId);
    } else {
      _update(state.copyWith(progress: {...state.progress, taskId: p.copyWith(count: count)}));
    }
  }

  /// Child taps "I prayed" during a prayer lock.
  void markPrayed() {
    final prayerTask = state.tasks.where((t) => t.kind == TaskKind.prayer).firstOrNull;
    if (prayerTask != null) submit(prayerTask.id);
  }

  /// Called by the native layer when a game session starts (or for the demo button).
  /// Returns the minutes actually granted.
  int consumeMinutes(int minutes) {
    if (!state.gamesUnlocked) return 0;
    final granted = minutes.clamp(0, state.remainingMinutes);
    _update(state.copyWith(usedMinutes: state.usedMinutes + granted));
    return granted;
  }

  // ---- parent actions (guarded by the parent PIN in the UI) -----------------

  void approve(String taskId) {
    _setStatus(taskId, TaskStatus.done);
    final def = state.tasks.firstWhere((t) => t.id == taskId);
    if (def.kind == TaskKind.prayer && state.prayerLock) {
      _update(state.copyWith(prayerLock: false, clearLockedPrayer: true));
    }
  }

  void reject(String taskId) {
    final p = state.progressOf(taskId);
    _update(state.copyWith(progress: {
      ...state.progress,
      taskId: p.copyWith(status: TaskStatus.todo, count: 0),
    }));
  }

  void upsertTask(TaskDefinition def) {
    final tasks = [...state.tasks.where((t) => t.id != def.id), def];
    _update(state.copyWith(tasks: tasks));
  }

  void removeTask(String taskId) {
    _update(state.copyWith(tasks: state.tasks.where((t) => t.id != taskId).toList()));
  }

  // ---- prayer lock ----------------------------------------------------------

  void startPrayerLock(Prayer prayer) {
    if (state.prayerLock && state.lockedPrayer == prayer) return; // already locked (app + native alarm)
    final prayerTask = state.tasks.where((t) => t.kind == TaskKind.prayer).firstOrNull;
    final progress = {...state.progress};
    if (prayerTask != null) progress[prayerTask.id] = const TaskProgress();
    _update(state.copyWith(prayerLock: true, lockedPrayer: prayer, progress: progress));
    _repo.notifyParent(_childId, 'adhan', data: {'prayer': prayer.name});
  }

  // ---- internals ------------------------------------------------------------

  void _setStatus(String taskId, TaskStatus status, {String? notifyType}) {
    final p = state.progressOf(taskId);
    _update(state.copyWith(progress: {...state.progress, taskId: p.copyWith(status: status)}));
    if (notifyType != null) _repo.notifyParent(_childId, notifyType, data: {'taskId': taskId});
  }

  void _update(WalletState next) {
    state = next;
    _persist(next);
    _repo.saveDay(_childId, next.toFamilyDay());
  }

  void _applyRemote(FamilyDay remote) {
    if (remote.day != state.day) return;
    state = state.copyWith(
      progress: remote.progress.map((k, v) => MapEntry(k, TaskProgress.fromJson(v))),
      usedMinutes: remote.usedMinutes,
      prayerLock: remote.prayerLock,
    );
    _persist(state);
  }

  WalletState _restore(String today) {
    final prefs = ref.read(sharedPrefsProvider);
    final raw = prefs.getString(_storageKey);
    final tasksRaw = prefs.getString('$_storageKey.tasks');
    final tasks = tasksRaw == null
        ? defaultTasks
        : (jsonDecode(tasksRaw) as List).map((e) => TaskDefinition.fromJson(e as Map<String, dynamic>)).toList();
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['day'] == today) {
        final day = FamilyDay.fromJson(j);
        return WalletState(
          day: today,
          tasks: tasks,
          progress: day.progress.map((k, v) => MapEntry(k, TaskProgress.fromJson(v))),
          usedMinutes: day.usedMinutes,
          prayerLock: day.prayerLock,
        );
      }
    }
    // New day: everything resets, task definitions stay.
    return WalletState(day: today, tasks: tasks, progress: const {});
  }

  void _persist(WalletState s) {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(_storageKey, jsonEncode(s.toFamilyDay().toJson()));
    prefs.setString('$_storageKey.tasks', jsonEncode(s.tasks.map((t) => t.toJson()).toList()));
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final walletProvider = NotifierProvider<WalletController, WalletState>(WalletController.new);
