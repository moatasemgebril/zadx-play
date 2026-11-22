import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/catalog/default_tasks.dart';
import '../../data/models/child_profile.dart';
import '../../data/models/family_task.dart';
import '../../services/family/approval_queue.dart';
import '../../services/family/child_storage.dart';
import '../../services/family/children_controller.dart';
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
    this.prayerLockSince,
    this.approved,
    this.prayerPaused = false,
  });

  final String day;
  final List<TaskDefinition> tasks;
  final Map<String, TaskProgress> progress;
  final int usedMinutes;
  final bool prayerLock;
  final Prayer? lockedPrayer;

  /// When the current prayer lock started (UTC). Plans without tasks (Free) end the lock
  /// automatically after the prayer window (see `lockStateFor`).
  final DateTime? prayerLockSince;

  /// Synced family: the server's credits {taskId: minutes} (written only by the `approveTask`
  /// Cloud Function for a parent device, R-32). A task counts as approved, and earns minutes,
  /// only with an entry here, whatever `progress` says. Null for a local-only family, where an
  /// approval on this device (behind the parent PIN) sets the task to done.
  final Map<String, int>? approved;

  /// Excused today (set by a parent behind the PIN): prayer tasks and the prayer lock are paused
  /// for this child. Prayer tasks then count for nothing either way (no stars or minutes lost),
  /// and the child sees only "your other tasks are open today", never a reason.
  final bool prayerPaused;

  /// Today's tasks for this child: prayer tasks are left out while [prayerPaused].
  List<TaskDefinition> get activeTasks =>
      prayerPaused ? tasks.where((t) => t.kind != TaskKind.prayer).toList() : tasks;

  /// True when the parent approved [id] today.
  bool isApproved(String id) =>
      approved != null ? approved!.containsKey(id) : progressOf(id).status == TaskStatus.done;

  /// True when a Free-plan prayer lock that started at [prayerLockSince] is over at [now].
  bool prayerWindowOver(DateTime now, Duration window) =>
      prayerLock && prayerLockSince != null && !now.toUtc().isBefore(prayerLockSince!.toUtc().add(window));

  TaskProgress progressOf(String id) => progress[id] ?? const TaskProgress();

  bool get requiredDone => activeTasks.where((t) => t.required).every((t) => isApproved(t.id));

  int get earnedMinutes => approved != null
      ? approved!.values.fold(0, (sum, m) => sum + m)
      : tasks.where((t) => progressOf(t.id).status == TaskStatus.done).fold(0, (sum, t) => sum + t.rewardMinutes);

  int get remainingMinutes => (earnedMinutes - usedMinutes).clamp(0, 1 << 30);

  /// Device games are playable only when all three conditions hold.
  bool get gamesUnlocked => requiredDone && !prayerLock && remainingMinutes > 0;

  int get doneCount => activeTasks.where((t) => isApproved(t.id)).length;

  /// Submissions waiting for a parent. "I prayed" can wait again at the next adhan even though
  /// the prayer task was already credited today (a second approval ends the lock, no new minutes).
  List<TaskDefinition> get pending => activeTasks
      .where((t) =>
          progressOf(t.id).status == TaskStatus.pending &&
          (approved == null || !approved!.containsKey(t.id) || t.kind == TaskKind.prayer))
      .toList();

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
    DateTime? prayerLockSince,
    Map<String, int>? approved,
    bool? prayerPaused,
  }) =>
      WalletState(
        day: day ?? this.day,
        tasks: tasks ?? this.tasks,
        progress: progress ?? this.progress,
        usedMinutes: usedMinutes ?? this.usedMinutes,
        prayerLock: prayerLock ?? this.prayerLock,
        lockedPrayer: clearLockedPrayer ? null : (lockedPrayer ?? this.lockedPrayer),
        prayerLockSince: clearLockedPrayer ? null : (prayerLockSince ?? this.prayerLockSince),
        approved: approved ?? this.approved,
        prayerPaused: prayerPaused ?? this.prayerPaused,
      );

  FamilyDay toFamilyDay() => FamilyDay(
        day: day,
        progress: progress.map((k, v) => MapEntry(k, v.toJson())),
        usedMinutes: usedMinutes,
        prayerLock: prayerLock,
        earnedMinutes: earnedMinutes,
        requiredDone: requiredDone,
        prayerLockSinceMs: prayerLock ? prayerLockSince?.toUtc().millisecondsSinceEpoch : null,
        approved: approved,
        prayerPaused: prayerPaused,
      );
}

/// Most minutes one task can earn (backend MAX_TASK_MINUTES); the server enforces it too.
const maxTaskMinutes = 120;

enum LockReason { prayer, requiredTasks, noTime }

/// Business rules for tasks and play time. UI and native lock code only *read*
/// [WalletState]; every change goes through this controller.
///
/// Each child has its own wallet (tasks, progress, minutes, prayer lock). This
/// controller always serves the active child ([activeChildIdProvider]) and
/// rebuilds when the parent switches child.
class WalletController extends Notifier<WalletState> {
  StreamSubscription<FamilyDay>? _remoteSub;
  String _childId = ChildProfile.defaultId;

  FamilyRepository get _repo => ref.read(familyRepositoryProvider);

  @override
  WalletState build() {
    _childId = ref.watch(activeChildIdProvider);
    // Rebuild only when the date changes (not every minute).
    final today = ref.watch(cityNowProvider.select((n) => dayKey(n.local)));
    // Re-subscribes automatically when the device is paired to another family.
    final repo = ref.watch(familyRepositoryProvider);
    final restored = restoreFrom(ref.read(sharedPrefsProvider), _childId, today, serverApprovals: repo.serverApprovals);
    _remoteSub?.cancel();
    _remoteSub = repo.watchDay(_childId, today).listen(_applyRemote);
    ref.onDispose(() => _remoteSub?.cancel());
    // Parent device: approvals taken offline reach the server now (no-op when nothing is queued).
    if (repo.serverApprovals) {
      Future.microtask(() => _queue.flush(repo, ref.read(familyIdProvider)));
    }

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

  /// Plans without tasks (Free): records screen minutes against the parent's daily limit
  /// instead of earned minutes. See `lockStateFor` in app_lock_service.dart.
  void addUsedMinutes(int minutes, {required int cap}) {
    final next = (state.usedMinutes + minutes.clamp(0, 60)).clamp(0, cap < 0 ? 0 : cap);
    if (next == state.usedMinutes) return;
    _update(state.copyWith(usedMinutes: next));
  }

  // ---- parent actions (guarded by the parent PIN in the UI) -----------------
  //
  // Local-only family: the decision is applied on this device, as before.
  // Synced family (R-32): the SERVER decides. `approveTask` / `rejectTask` check server-side that
  // this is a parent device and credit the minutes; the result comes back through [watchDay].
  // Offline, the decision is queued here and sent when online. A paired child device cannot
  // approve, even with the PIN (the server would refuse): these return false and the UI asks
  // the parent to approve from the parent phone.

  ApprovalQueue get _queue => ApprovalQueue(ref.read(sharedPrefsProvider));

  /// False when this device may not approve (a paired child device in a synced family).
  bool get canApprove => !_repo.serverApprovals || !ref.read(childrenProvider).isBound;

  bool approve(String taskId) {
    final def = state.tasks.where((t) => t.id == taskId).firstOrNull;
    if (def == null || !canApprove) return false;
    final lockEnds = def.kind == TaskKind.prayer && state.prayerLock;
    final p = state.progressOf(taskId);
    var next = state.copyWith(progress: {...state.progress, taskId: p.copyWith(status: TaskStatus.done)});
    if (_repo.serverApprovals) {
      // Shown right away on this parent device; the server's credits replace it on the next snapshot.
      final minutes = def.rewardMinutes.clamp(0, maxTaskMinutes);
      next = next.copyWith(approved: {...?state.approved}..putIfAbsent(taskId, () => minutes));
      _sendDecision(PendingApproval(
        approve: true,
        familyId: ref.read(familyIdProvider) ?? '',
        childId: _childId,
        day: state.day,
        taskId: taskId,
        minutes: minutes,
        requiredTaskIds: state.activeTasks.where((t) => t.required).map((t) => t.id).toList(),
        isPrayer: def.kind == TaskKind.prayer,
      ));
    }
    if (lockEnds) next = next.copyWith(prayerLock: false, clearLockedPrayer: true);
    _update(next, lockChanged: lockEnds);
    return true;
  }

  /// Parent only (behind the PIN; a paired child device cannot, and the server rules refuse it):
  /// pauses or resumes prayer tasks and the prayer lock for the active child, for today only.
  /// Pausing ends a running prayer lock. Nothing is sent to the family log or other children.
  bool setPrayerPaused(bool paused) {
    if (!canApprove) return false;
    if (state.prayerPaused == paused) return true;
    final endsLock = paused && state.prayerLock;
    var next = state.copyWith(prayerPaused: paused);
    if (endsLock) next = next.copyWith(prayerLock: false, clearLockedPrayer: true);
    state = next;
    _persist(next);
    if (_repo.serverApprovals) {
      _repo.setPrayerPaused(childId: _childId, day: next.day, paused: paused).catchError((Object e) {
        debugPrint('prayer pause sync failed: $e');
      });
    }
    return true;
  }

  bool reject(String taskId) {
    if (!canApprove) return false;
    final p = state.progressOf(taskId);
    _update(state.copyWith(progress: {
      ...state.progress,
      taskId: p.copyWith(status: TaskStatus.todo, count: 0),
    }));
    if (_repo.serverApprovals) {
      _sendDecision(PendingApproval(
        approve: false,
        familyId: ref.read(familyIdProvider) ?? '',
        childId: _childId,
        day: state.day,
        taskId: taskId,
      ));
    }
    return true;
  }

  void _sendDecision(PendingApproval item) {
    final repo = _repo;
    final queue = _queue;
    // Older queued decisions go first, so the server sees them in order.
    unawaited(queue.flush(repo, item.familyId).then((_) => queue.send(repo, item)));
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
    if (state.prayerPaused) return; // excused today: no prayer lock, no task reset, no notification
    if (state.prayerLock && state.lockedPrayer == prayer) return; // already locked (app + native alarm)
    final prayerTask = state.tasks.where((t) => t.kind == TaskKind.prayer).firstOrNull;
    final progress = {...state.progress};
    if (prayerTask != null) progress[prayerTask.id] = const TaskProgress();
    _update(
      state.copyWith(
        prayerLock: true,
        lockedPrayer: prayer,
        progress: progress,
        prayerLockSince: DateTime.now().toUtc(),
      ),
      lockChanged: true,
    );
    _repo.notifyParent(_childId, 'adhan', data: {'prayer': prayer.name});
  }

  /// Plans without tasks (Free): there is no "I prayed" approval, so the prayer lock ends by
  /// itself once the prayer window ([window], measured from the lock start) is over.
  /// Returns true when the lock was ended.
  bool endPrayerLockIfOver(DateTime now, Duration window) {
    if (!state.prayerWindowOver(now, window)) return false;
    _update(state.copyWith(prayerLock: false, clearLockedPrayer: true), lockChanged: true);
    return true;
  }

  // ---- internals ------------------------------------------------------------

  void _setStatus(String taskId, TaskStatus status, {String? notifyType}) {
    final p = state.progressOf(taskId);
    _update(state.copyWith(progress: {...state.progress, taskId: p.copyWith(status: status)}));
    if (notifyType != null) _repo.notifyParent(_childId, notifyType, data: {'taskId': taskId});
  }

  /// [lockChanged]: this change starts or ends the prayer lock (only then is the lock synced).
  void _update(WalletState next, {bool lockChanged = false}) {
    state = next;
    _persist(next);
    _repo.saveDay(_childId, next.toFamilyDay(), lockChanged: lockChanged).catchError((Object e) {
      debugPrint('day sync failed: $e');
    });
  }

  void _applyRemote(FamilyDay remote) {
    if (remote.day != state.day) return;
    // The window of a Free prayer lock counts from the later of the device time and the server
    // time the lock reached Firestore. `prayerLockSinceMs` is not synced (the repository drops it),
    // so a back-dated device time cannot shorten the lock.
    final sinceMs = [remote.prayerLockSinceMs, remote.prayerLockAtMs].whereType<int>().fold<int?>(
        null, (a, b) => a == null || b > a ? b : a);
    state = state.copyWith(
      progress: remote.progress.map((k, v) => MapEntry(k, TaskProgress.fromJson(v))),
      usedMinutes: remote.usedMinutes,
      prayerLock: remote.prayerLock,
      clearLockedPrayer: !remote.prayerLock,
      prayerLockSince: remote.prayerLock ? _sinceOrNow(sinceMs, state.prayerLockSince) : null,
      approved: remote.approved,
      prayerPaused: remote.prayerPaused,
    );
    _persist(state);
  }

  /// Loads [childId]'s saved wallet for [today] (new day → progress resets,
  /// task definitions stay). Also used for the per-child summaries.
  /// [serverApprovals]: synced family, where only the server's credits count (R-32).
  static WalletState restoreFrom(SharedPreferences prefs, String childId, String today, {bool serverApprovals = false}) {
    final raw = prefs.getString(ChildStorage.walletKey(childId));
    final tasksRaw = prefs.getString(ChildStorage.tasksKey(childId));
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
          prayerLockSince: day.prayerLock ? _sinceOrNow(day.prayerLockSinceMs, null) : null,
          approved: day.approved ?? (serverApprovals ? const {} : null),
          prayerPaused: day.prayerPaused,
        );
      }
    }
    // New day: everything resets, task definitions stay.
    return WalletState(day: today, tasks: tasks, progress: const {}, approved: serverApprovals ? const {} : null);
  }

  /// A prayer lock saved without a start time (older version or another device) counts from
  /// now, so a Free lock always ends after at most one prayer window.
  static DateTime _sinceOrNow(int? ms, DateTime? fallback) =>
      ms != null ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : (fallback ?? DateTime.now().toUtc());

  void _persist(WalletState s) {
    final prefs = ref.read(sharedPrefsProvider);
    prefs.setString(ChildStorage.walletKey(_childId), jsonEncode(s.toFamilyDay().toJson()));
    prefs.setString(ChildStorage.tasksKey(_childId), jsonEncode(s.tasks.map((t) => t.toJson()).toList()));
  }

  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

final walletProvider = NotifierProvider<WalletController, WalletState>(WalletController.new);
