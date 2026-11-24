import 'package:flutter/material.dart';

import '../../core/app_variant.dart';
import '../../core/localized.dart';
import '../models/family_task.dart';

/// Starter tasks for a new family. Parents can edit/add from the dashboard.
const defaultTasks = <TaskDefinition>[
  TaskDefinition(id: 'prayer', title: Localized('الصلاة في وقتها', 'Pray on time'), subtitle: Localized('مع كل أذان', 'At every adhan'), kind: TaskKind.prayer, rewardMinutes: 10, color: Color(0xFF6C3BEB), required: true),
  TaskDefinition(id: 'homework', title: Localized('الواجب المدرسي', 'Homework'), subtitle: Localized('واجب النهارده كامل', "All of today's homework"), kind: TaskKind.homework, rewardMinutes: 20, color: Color(0xFF4CC9F0), required: true),
  TaskDefinition(id: 'falaq', title: Localized('حفظ سورة الفلق', 'Memorize Surah Al-Falaq'), subtitle: Localized('تسميع لبابا أو ماما', 'Recite it to a parent'), kind: TaskKind.quran, rewardMinutes: 20, color: Color(0xFFFFC83D)),
  TaskDefinition(id: 'adhkar_morning', title: Localized('أذكار الصباح', 'Morning adhkar'), subtitle: Localized('من صفحة القرآن ← الأذكار', 'Quran tab → Adhkar'), kind: TaskKind.adhkar, rewardMinutes: 10, color: Color(0xFF7ED9B8)),
  TaskDefinition(id: 'adhkar_evening', title: Localized('أذكار المساء', 'Evening adhkar'), subtitle: Localized('من صفحة القرآن ← الأذكار', 'Quran tab → Adhkar'), kind: TaskKind.adhkar, rewardMinutes: 10, color: Color(0xFFC4B5FD)),
  TaskDefinition(id: 'room', title: Localized('ترتيب الأوضة', 'Tidy your room'), subtitle: Localized('السرير والألعاب', 'Bed and toys'), kind: TaskKind.chore, rewardMinutes: 10, color: Color(0xFFFF6B6B)),
  // Exercises
  TaskDefinition(id: 'pushup', title: Localized('تمرين ضغط', 'Push-ups'), subtitle: Localized('تمرين', 'Exercise'), kind: TaskKind.exercise, rewardMinutes: 10, color: Color(0xFFFF6B6B), reps: 10),
  TaskDefinition(id: 'situp', title: Localized('تمرين بطن', 'Sit-ups'), subtitle: Localized('تمرين', 'Exercise'), kind: TaskKind.exercise, rewardMinutes: 10, color: Color(0xFF4CC9F0), reps: 15),
  TaskDefinition(id: 'jacks', title: Localized('قفز (جامبينج جاك)', 'Jumping jacks'), subtitle: Localized('تمرين', 'Exercise'), kind: TaskKind.exercise, rewardMinutes: 5, color: Color(0xFFFFC83D), reps: 20),
  TaskDefinition(id: 'squat', title: Localized('سكوات', 'Squats'), subtitle: Localized('تمرين', 'Exercise'), kind: TaskKind.exercise, rewardMinutes: 5, color: Color(0xFF2DBE7E), reps: 10),
  TaskDefinition(id: 'toes', title: Localized('لمس أصابع القدم', 'Toe touches'), subtitle: Localized('تمرين', 'Exercise'), kind: TaskKind.exercise, rewardMinutes: 5, color: Color(0xFFC4B5FD), reps: 10),
];

/// Task kinds that exist only in Zad X Play (prayer, Quran memorisation, adhkar).
const islamicTaskKinds = {TaskKind.prayer, TaskKind.quran, TaskKind.adhkar};

/// Starter tasks of [variant]: Zad X Kids gets the same list without the Islamic tasks
/// (homework stays the must-do task). New shared tasks added to [defaultTasks] appear in both apps.
List<TaskDefinition> starterTasksFor(AppVariant variant) => variant == AppVariant.kids
    ? [for (final t in defaultTasks) if (!islamicTaskKinds.contains(t.kind)) t]
    : defaultTasks;

/// Starter tasks of this build.
final List<TaskDefinition> starterTasks = starterTasksFor(appVariant);
