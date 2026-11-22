import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/localized.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../../variant/kids_strings.dart';
import 'schedule_controller.dart';

/// Zad X Kids text for a schedule kind.
extension ScheduleKindText on ScheduleKind {
  Localized get title => switch (this) {
        ScheduleKind.bedtime => KidsText.bedtime,
        ScheduleKind.study => KidsText.study,
        ScheduleKind.reading => KidsText.reading,
      };

  Localized get note => switch (this) {
        ScheduleKind.bedtime => KidsText.bedtimeNote,
        ScheduleKind.study => KidsText.studyNote,
        ScheduleKind.reading => KidsText.readingNote,
      };

  /// Games-screen banner while this schedule locks the device.
  Localized get lockBanner => switch (this) {
        ScheduleKind.bedtime => KidsText.lockBedtime,
        ScheduleKind.study => KidsText.lockStudy,
        ScheduleKind.reading => KidsText.lockReading,
      };

  IconData get icon => switch (this) {
        ScheduleKind.bedtime => Icons.bed_rounded, // a bed, not a crescent (Kids artwork rules)
        ScheduleKind.study => Icons.menu_book_rounded,
        ScheduleKind.reading => Icons.auto_stories_rounded,
      };

  Color get color => switch (this) {
        ScheduleKind.bedtime => AppColors.purple,
        ScheduleKind.study => AppColors.sky,
        ScheduleKind.reading => AppColors.mint,
      };
}

String _time(int minute, String lang) => Fmt.hours(minute / 60, lang);

String scheduleRange(ScheduledLock s, String lang) => '${_time(s.startMinute, lang)} – ${_time(s.endMinute, lang)}';

/// Home (Zad X Kids): today's study / bedtime / reading times, the active one highlighted.
class ScheduleTodayCard extends ConsumerWidget {
  const ScheduleTodayCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = context.lang;
    final schedules = ref.watch(scheduleProvider);
    final active = ref.watch(activeScheduleProvider);
    final today = DateTime.now().weekday;
    final shown = [for (final s in schedules) if (s.enabled && s.weekdays.contains(today)) s];

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(KidsText.todayTitle.of(lang), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (shown.isEmpty) Text(KidsText.off.of(lang), style: const TextStyle(fontSize: 15, color: AppColors.muted)),
        for (final s in shown)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: s.kind == active?.kind ? s.kind.color : AppColors.cream,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(s.kind.icon, color: s.kind == active?.kind ? Colors.white : s.kind.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.kind == active?.kind ? '${s.kind.title.of(lang)} · ${KidsText.lockedNow.of(lang)}' : s.kind.title.of(lang),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: s.kind == active?.kind ? Colors.white : AppColors.ink),
                ),
              ),
              Text(
                scheduleRange(s, lang),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: s.kind == active?.kind ? Colors.white : AppColors.ink),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Parent area (Zad X Kids): turn each schedule on/off and pick its times and days.
class ScheduleSettingsCard extends ConsumerWidget {
  const ScheduleSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = context.lang;
    final schedules = ref.watch(scheduleProvider);
    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(KidsText.schedulesTitle.of(lang), style: Theme.of(context).textTheme.titleMedium),
        Text(KidsText.schedulesNote.of(lang), style: const TextStyle(fontSize: 14, color: AppColors.muted)),
        for (final s in schedules) ...[
          const Divider(height: 24),
          _ScheduleEditor(schedule: s),
        ],
      ]),
    );
  }
}

class _ScheduleEditor extends ConsumerWidget {
  const _ScheduleEditor({required this.schedule});
  final ScheduledLock schedule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = context.lang;
    final ctrl = ref.read(scheduleProvider.notifier);
    final s = schedule;

    Future<void> pick({required bool start}) async {
      final m = start ? s.startMinute : s.endMinute;
      final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
      if (t == null) return;
      final minute = t.hour * 60 + t.minute;
      ctrl.save(start ? s.copyWith(startMinute: minute) : s.copyWith(endMinute: minute));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        secondary: Icon(s.kind.icon, color: s.kind.color),
        title: Text(s.kind.title.of(lang), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        subtitle: Text(s.kind.note.of(lang), style: const TextStyle(fontSize: 14)),
        value: s.enabled,
        onChanged: (v) => ctrl.save(s.copyWith(enabled: v)),
      ),
      if (s.enabled) ...[
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => pick(start: true),
              child: Text('${KidsText.from.of(lang)} ${_time(s.startMinute, lang)}', style: const TextStyle(fontSize: 15)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => pick(start: false),
              child: Text('${KidsText.to.of(lang)} ${_time(s.endMinute, lang)}', style: const TextStyle(fontSize: 15)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Text(KidsText.days.of(lang), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (var d = DateTime.monday; d <= DateTime.sunday; d++)
            FilterChip(
              label: Text(KidsText.weekdays[d - 1].of(lang), style: const TextStyle(fontSize: 14)),
              selected: s.weekdays.contains(d),
              onSelected: (on) => ctrl.save(s.copyWith(weekdays: on ? {...s.weekdays, d} : ({...s.weekdays}..remove(d)))),
            ),
        ]),
      ],
    ]);
  }
}
