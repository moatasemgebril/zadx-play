import 'package:flutter/material.dart';

import '../../core/localized.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/family_task.dart';

/// The two reading homework tasks a parent can switch on (Parent → Reading homework).
///
/// They are ordinary [TaskDefinition]s of kind [TaskKind.reading], so they go through the
/// normal wallet flow: the child hands the task in (status `pending`), the parent approves
/// it behind the PIN, and only then are the reward minutes earned.
abstract final class ReadingTasks {
  static const storyId = 'reading_story';
  static const bookId = 'reading_book';

  /// Paper-book reading times the parent can choose.
  static const minuteChoices = <int>[10, 15, 20];
  static const defaultMinutes = 15;

  /// Same reward as the other bonus tasks.
  static const rewardMinutes = 10;

  static TaskDefinition story(ReadingLevel level) => TaskDefinition(
        id: storyId,
        title: const Localized('قراءة قصة', 'Read a story'),
        subtitle: const Localized('قصة قصيرة وأسئلة عليها', 'A short story + questions'),
        kind: TaskKind.reading,
        rewardMinutes: rewardMinutes,
        color: const Color(0xFF4CC9F0),
        readingMode: ReadingMode.story,
        readingLevel: level,
      );

  static TaskDefinition book(int minutes) => TaskDefinition(
        id: bookId,
        title: const Localized('قراءة في كتاب ورقي', 'Read a paper book'),
        subtitle: Localized('${Fmt.digits(minutes, 'ar')} دقيقة قراءة', '$minutes minutes of reading'),
        kind: TaskKind.reading,
        rewardMinutes: rewardMinutes,
        color: const Color(0xFF2DBE7E),
        readingMode: ReadingMode.paperBook,
        readingMinutes: minutes,
      );
}
