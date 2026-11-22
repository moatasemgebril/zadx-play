import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings/settings_controller.dart';

/// Progress of one paper-book reading timer (one task, one child, one day).
///
/// [seconds] only grows while the timer screen is open, Zad X is in the foreground and the
/// child pressed Start: it is counted tick by tick, never from the wall clock, so moving the
/// phone's clock cannot finish a reading task. [running] is what the child last chose; a timer
/// that was running when Zad X was closed comes back paused (the gap is never counted).
@immutable
class ReadingTimerProgress {
  const ReadingTimerProgress({required this.day, this.seconds = 0, this.running = false, this.startedAtMs});

  /// The wallet day (yyyy-MM-dd) the progress belongs to: a new day starts from zero.
  final String day;

  /// Seconds read so far.
  final int seconds;

  /// True while the child has the timer running (false = paused / not started).
  final bool running;

  /// When the child first pressed Start (epoch ms, for the parent / support only).
  final int? startedAtMs;

  ReadingTimerProgress copyWith({int? seconds, bool? running, int? startedAtMs}) => ReadingTimerProgress(
        day: day,
        seconds: seconds ?? this.seconds,
        running: running ?? this.running,
        startedAtMs: startedAtMs ?? this.startedAtMs,
      );

  Map<String, Object?> toJson() => {
        'day': day,
        'seconds': seconds,
        'running': running,
        if (startedAtMs != null) 'startedAtMs': startedAtMs,
      };

  /// Null for anything malformed.
  static ReadingTimerProgress? fromJson(Object? json) {
    if (json is! Map) return null;
    final day = json['day'];
    final seconds = json['seconds'];
    if (day is! String || seconds is! int || seconds < 0) return null;
    final started = json['startedAtMs'];
    return ReadingTimerProgress(
      day: day,
      seconds: seconds,
      running: json['running'] == true,
      startedAtMs: started is int ? started : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReadingTimerProgress &&
      other.day == day &&
      other.seconds == seconds &&
      other.running == running &&
      other.startedAtMs == startedAtMs;

  @override
  int get hashCode => Object.hash(day, seconds, running, startedAtMs);
}

/// Keeps each child's paper-book timer on the device (local storage only, never uploaded), so
/// leaving the screen or the app does not reset it.
class ReadingTimerStore {
  ReadingTimerStore(this._prefs);

  final SharedPreferences _prefs;

  static String keyFor(String childId, String taskId) => 'reading.timer.v1.$childId.$taskId';

  /// Today's progress, or a fresh one. A timer saved as running comes back paused.
  ReadingTimerProgress load(String childId, String taskId, String day) {
    try {
      final raw = _prefs.getString(keyFor(childId, taskId));
      final saved = raw == null ? null : ReadingTimerProgress.fromJson(jsonDecode(raw));
      if (saved == null || saved.day != day) return ReadingTimerProgress(day: day);
      return saved.copyWith(running: false);
    } catch (e) {
      debugPrint('reading timer unreadable: $e');
      return ReadingTimerProgress(day: day);
    }
  }

  Future<void> save(String childId, String taskId, ReadingTimerProgress progress) =>
      _prefs.setString(keyFor(childId, taskId), jsonEncode(progress.toJson()));

  /// After the task is handed in.
  Future<void> clear(String childId, String taskId) => _prefs.remove(keyFor(childId, taskId));
}

final readingTimerStoreProvider = Provider<ReadingTimerStore>((ref) => ReadingTimerStore(ref.watch(sharedPrefsProvider)));
