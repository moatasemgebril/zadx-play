import 'package:flutter/material.dart';

import '../../core/localized.dart';

enum TaskKind { prayer, homework, quran, adhkar, chore, exercise, custom }

enum TaskStatus { todo, pending, done }

/// A task definition the parent sets up. Daily progress lives in [TaskProgress].
class TaskDefinition {
  const TaskDefinition({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.rewardMinutes,
    required this.color,
    this.required = false,
    this.reps,
  });

  final String id;
  final Localized title;
  final Localized subtitle;
  final TaskKind kind;
  final int rewardMinutes;
  final Color color;

  /// Must-do tasks gate all device games.
  final bool required;

  /// For exercises: how many repetitions complete the task.
  final int? reps;

  bool get isExercise => kind == TaskKind.exercise;

  Map<String, dynamic> toJson() => {
        'id': id,
        'titleAr': title.ar,
        'titleEn': title.en,
        'subAr': subtitle.ar,
        'subEn': subtitle.en,
        'kind': kind.name,
        'rewardMinutes': rewardMinutes,
        'color': color.toARGB32(),
        'required': required,
        'reps': reps,
      };

  factory TaskDefinition.fromJson(Map<String, dynamic> j) => TaskDefinition(
        id: j['id'] as String,
        title: Localized(j['titleAr'] as String, j['titleEn'] as String),
        subtitle: Localized(j['subAr'] as String, j['subEn'] as String),
        kind: TaskKind.values.byName(j['kind'] as String),
        rewardMinutes: j['rewardMinutes'] as int,
        color: Color(j['color'] as int),
        required: j['required'] as bool? ?? false,
        reps: j['reps'] as int?,
      );
}

/// Today's state of one task for one child.
class TaskProgress {
  const TaskProgress({this.status = TaskStatus.todo, this.count = 0});

  final TaskStatus status;
  final int count;

  TaskProgress copyWith({TaskStatus? status, int? count}) =>
      TaskProgress(status: status ?? this.status, count: count ?? this.count);

  Map<String, dynamic> toJson() => {'status': status.name, 'count': count};

  factory TaskProgress.fromJson(Map<String, dynamic> j) => TaskProgress(
        status: TaskStatus.values.byName(j['status'] as String? ?? 'todo'),
        count: j['count'] as int? ?? 0,
      );
}
