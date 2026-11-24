import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../data/catalog/reading_stories.dart';
import '../../data/models/family_task.dart';
import '../../l10n/app_localizations.dart';
import '../../services/family/children_controller.dart';
import '../../shared/widgets/zad_widgets.dart';
import '../tasks/wallet_controller.dart';
import 'reading_timer_store.dart';

/// Child-facing screen for a reading homework task ([TaskKind.reading]).
///
/// * Story: pick a built-in story of the parent's level, read it, answer its questions.
/// * Paper book: read for the parent's minutes with a calm timer.
///
/// Either way the child only *hands the task in* ([WalletController.submit] → `pending`).
/// The reward is earned when the parent approves it behind the PIN, exactly like every
/// other task. Works offline; no microphone, camera or network.
class ReadingTaskScreen extends ConsumerWidget {
  const ReadingTaskScreen({super.key, required this.taskId});

  final String taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = context.lang;
    final wallet = ref.watch(walletProvider);
    TaskDefinition? task;
    for (final t in wallet.tasks) {
      if (t.id == taskId && t.isReading) task = t;
    }
    final status = wallet.progressOf(taskId).status;

    final Widget body;
    if (task == null) {
      body = _Message(text: l10n.readingTaskMissing);
    } else if (task.readingMode == ReadingMode.paperBook) {
      body = PaperBookReading(task: task, status: status);
    } else {
      body = StoryReading(task: task, status: status);
    }

    return Scaffold(
      backgroundColor: AppColors.pageTints['tasks'],
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(task?.title.of(lang) ?? l10n.readingSetupTitle),
      ),
      body: SafeArea(child: body),
    );
  }
}

// ---------------------------------------------------------------------------- story

/// Story flow: pick → read → questions → handed in.
class StoryReading extends ConsumerStatefulWidget {
  const StoryReading({super.key, required this.task, required this.status});

  final TaskDefinition task;
  final TaskStatus status;

  @override
  ConsumerState<StoryReading> createState() => _StoryReadingState();
}

class _StoryReadingState extends ConsumerState<StoryReading> {
  ReadingStory? _story;
  bool _readDone = false;
  int _question = 0;
  final Set<int> _wrong = {};
  bool _answeredRight = false;
  bool _handedIn = false;

  void _pick(ReadingStory s) => setState(() {
        _story = s;
        _readDone = false;
        _question = 0;
        _wrong.clear();
        _answeredRight = false;
      });

  void _answer(int index) {
    final q = _story!.questions[_question];
    setState(() {
      if (index == q.answer) {
        _answeredRight = true;
      } else {
        _wrong.add(index);
      }
    });
  }

  void _next() {
    final story = _story!;
    if (_question + 1 < story.questions.length) {
      setState(() {
        _question++;
        _wrong.clear();
        _answeredRight = false;
      });
      return;
    }
    // Last question answered: hand the task in for the parent to confirm.
    if (ref.read(walletProvider).progressOf(widget.task.id).status == TaskStatus.todo) {
      ref.read(walletProvider.notifier).submit(widget.task.id);
    }
    setState(() => _handedIn = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_handedIn) return _Finished(title: l10n.readingFinishTitle);
    if (widget.status != TaskStatus.todo) return _StatusView(status: widget.status);
    final story = _story;
    if (story == null) return _picker(context);
    if (!_readDone) return _reader(context, story);
    return _questions(context, story);
  }

  Widget _picker(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    final stories = storiesFor(widget.task.readingLevel);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(l10n.readingPickStory, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
      const SizedBox(height: 12),
      for (final s in stories) ...[
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            key: Key('story_${s.id}'),
            borderRadius: BorderRadius.circular(20),
            onTap: () => _pick(s),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  const ExcludeSemantics(child: Icon(Icons.menu_book_rounded, size: 36, color: AppColors.purple)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.title.of(lang), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
                      Text(readingLevelLabel(l10n, s.level), style: const TextStyle(fontSize: 15, color: AppColors.muted)),
                    ]),
                  ),
                  const ExcludeSemantics(child: Icon(Icons.chevron_right_rounded, color: AppColors.purpleDark, size: 32)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _reader(BuildContext context, ReadingStory story) {
    final l10n = context.l10n;
    final lang = context.lang;
    // Bigger type for the youngest readers.
    final size = story.level == ReadingLevel.age5to7 ? 24.0 : 21.0;
    return ListView(padding: const EdgeInsets.all(16), children: [
      ZadCard(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            header: true,
            child: Text(story.title.of(lang), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.purpleDark)),
          ),
          const SizedBox(height: 12),
          for (final p in story.paragraphs) ...[
            Text(p.of(lang), style: TextStyle(fontSize: size, height: 1.7, color: AppColors.ink)),
            const SizedBox(height: 12),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        key: const Key('readingDoneButton'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: () => setState(() => _readDone = true),
        icon: const Icon(Icons.check_rounded),
        label: Text(l10n.readingDoneReading),
      ),
    ]);
  }

  Widget _questions(BuildContext context, ReadingStory story) {
    final l10n = context.l10n;
    final lang = context.lang;
    final q = story.questions[_question];
    final last = _question + 1 == story.questions.length;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
        l10n.readingQuestionOf(Fmt.digits(_question + 1, lang), Fmt.digits(story.questions.length, lang)),
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.muted),
      ),
      const SizedBox(height: 6),
      ProgressBar(value: (_question + (_answeredRight ? 1 : 0)) / story.questions.length, color: AppColors.mint),
      const SizedBox(height: 16),
      Semantics(
        header: true,
        child: Text(q.prompt.of(lang), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: AppColors.ink)),
      ),
      const SizedBox(height: 14),
      for (var i = 0; i < q.options.length; i++) ...[
        _OptionButton(
          key: Key('option_$i'),
          text: q.options[i].of(lang),
          state: _answeredRight && i == q.answer
              ? _OptionState.right
              : _wrong.contains(i)
                  ? _OptionState.wrong
                  : _OptionState.idle,
          onTap: _answeredRight || _wrong.contains(i) ? null : () => _answer(i),
        ),
        const SizedBox(height: 10),
      ],
      if (_wrong.isNotEmpty && !_answeredRight)
        Semantics(
          liveRegion: true,
          child: Banner2(text: l10n.readingTryAgain, bg: AppColors.pendingBg, fg: AppColors.pendingText, icon: Icons.lightbulb_rounded),
        ),
      if (_answeredRight) ...[
        Semantics(
          liveRegion: true,
          child: Banner2(text: l10n.readingCorrect, bg: AppColors.mintSoft, fg: AppColors.mintText, icon: Icons.check_rounded),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('readingNextButton'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _next,
          child: Text(last ? l10n.readingFinish : l10n.readingNext),
        ),
      ],
    ]);
  }
}

enum _OptionState { idle, right, wrong }

class _OptionButton extends StatelessWidget {
  const _OptionButton({super.key, required this.text, required this.state, required this.onTap});

  final String text;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (state) {
      _OptionState.idle => (Colors.white, AppColors.ink, AppColors.purple),
      _OptionState.right => (AppColors.mintSoft, AppColors.mintText, AppColors.mintText),
      _OptionState.wrong => (AppColors.lockBg, AppColors.lockText, AppColors.lockText),
    };
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg,
        disabledForegroundColor: fg,
        side: BorderSide(color: border, width: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onTap,
      child: Row(children: [
        Expanded(child: Text(text)),
        if (state == _OptionState.right) const Icon(Icons.check_circle_rounded),
        if (state == _OptionState.wrong) const Icon(Icons.close_rounded),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------- paper book

/// Paper-book flow: a calm countdown, then the child hands the task in for the parent.
/// The child cannot hand it in before the time is up.
///
/// The time read is kept per child and task for the day ([ReadingTimerStore]): leaving the
/// screen or Zad X pauses the timer instead of resetting it, and it continues from there. It only
/// counts while this screen is open and Zad X is in the foreground.
class PaperBookReading extends ConsumerStatefulWidget {
  const PaperBookReading({super.key, required this.task, required this.status});

  final TaskDefinition task;
  final TaskStatus status;

  @override
  ConsumerState<PaperBookReading> createState() => _PaperBookReadingState();
}

class _PaperBookReadingState extends ConsumerState<PaperBookReading> {
  Timer? _timer;
  late int _total;
  late int _left;
  bool _handedIn = false;

  // Saved progress (read in initState: `ref` must not be used in dispose).
  late final ReadingTimerStore _store;
  late final String _childId;
  late ReadingTimerProgress _progress;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final minutes = widget.task.readingMinutes ?? 15;
    _total = minutes.clamp(1, 120) * 60;
    _store = ref.read(readingTimerStoreProvider);
    _childId = ref.read(activeChildIdProvider);
    _progress = _store.load(_childId, widget.task.id, ref.read(walletProvider).day);
    _left = (_total - _progress.seconds).clamp(0, _total);
    // Zad X hidden (home button, another app, screen off): pause, never count time away.
    _lifecycle = AppLifecycleListener(onHide: _pause);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _pause(rebuild: false);
    super.dispose();
  }

  bool get _running => _timer != null;

  void _save() => unawaited(_store.save(_childId, widget.task.id, _progress));

  void _pause({bool rebuild = true}) {
    final wasRunning = _timer != null;
    _timer?.cancel();
    _timer = null;
    if (!wasRunning) return;
    _progress = _progress.copyWith(running: false);
    _save();
    if (rebuild && mounted) setState(() {});
  }

  void _start() {
    if (_running || _left <= 0) return;
    _progress = _progress.copyWith(running: true, startedAtMs: _progress.startedAtMs ?? DateTime.now().millisecondsSinceEpoch);
    _save();
    setState(() {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() {
          _left--;
          _progress = _progress.copyWith(seconds: (_total - _left).clamp(0, _total));
          if (_left <= 0) {
            _left = 0;
            t.cancel();
            _timer = null;
            _progress = _progress.copyWith(running: false);
          }
        });
        _save();
      });
    });
  }

  void _toggle() => _running ? _pause() : _start();

  void _handIn() {
    if (_left > 0) return;
    if (ref.read(walletProvider).progressOf(widget.task.id).status == TaskStatus.todo) {
      ref.read(walletProvider.notifier).submit(widget.task.id);
    }
    unawaited(_store.clear(_childId, widget.task.id));
    setState(() => _handedIn = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = context.lang;
    if (_handedIn) return _Finished(title: l10n.readingTimeUp);
    if (widget.status != TaskStatus.todo) return _StatusView(status: widget.status);

    final minutes = (_total / 60).round();
    final mm = (_left ~/ 60).toString().padLeft(2, '0');
    final ss = (_left % 60).toString().padLeft(2, '0');
    final time = Fmt.digits('$mm:$ss', lang);
    final done = _left == 0;

    return ListView(padding: const EdgeInsets.all(16), children: [
      ZadCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const ExcludeSemantics(child: Icon(Icons.auto_stories_rounded, size: 48, color: AppColors.mintText)),
          const SizedBox(height: 8),
          Text(l10n.readingBookTitle,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(l10n.readingBookNote(Fmt.digits(minutes, lang)),
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, height: 1.5, color: AppColors.muted)),
        ]),
      ),
      const SizedBox(height: 24),
      Center(
        child: Semantics(
          label: l10n.readingTimeLeft(time),
          excludeSemantics: true,
          child: SizedBox(
            width: 220,
            height: 220,
            child: Stack(fit: StackFit.expand, children: [
              CircularProgressIndicator(
                value: 1 - _left / _total,
                strokeWidth: 14,
                color: AppColors.mint,
                backgroundColor: AppColors.mintSoft,
              ),
              Center(
                child: Text(
                  time,
                  key: const Key('readingTimeText'),
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.ink),
                ),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 24),
      if (!done)
        FilledButton.icon(
          key: const Key('readingTimerButton'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _toggle,
          icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: Text(_running ? l10n.readingTimerPause : (_left == _total ? l10n.readingTimerStart : l10n.readingTimerResume)),
        )
      else ...[
        Semantics(
          liveRegion: true,
          child: Banner2(text: l10n.readingTimeUp, bg: AppColors.mintSoft, fg: AppColors.mintText, icon: Icons.star_rounded),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('readingSendButton'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _handIn,
          icon: const Icon(Icons.family_restroom_rounded),
          label: Text(l10n.readingSendToParent),
        ),
      ],
    ]);
  }
}

// ---------------------------------------------------------------------------- shared

String readingLevelLabel(AppLocalizations l10n, ReadingLevel level) => switch (level) {
      ReadingLevel.age5to7 => l10n.readingLevel5to7,
      ReadingLevel.age8to10 => l10n.readingLevel8to10,
      ReadingLevel.age11to12 => l10n.readingLevel11to12,
    };

class _Finished extends StatelessWidget {
  const _Finished({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      const ExcludeSemantics(child: Icon(Icons.star_rounded, size: 96, color: AppColors.yellow)),
      const SizedBox(height: 12),
      Semantics(
        liveRegion: true,
        child: Text(title,
            key: const Key('readingFinished'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.ink)),
      ),
      const SizedBox(height: 8),
      Text(l10n.readingSentToParent, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, color: AppColors.muted)),
      const SizedBox(height: 24),
      _BackButton(label: l10n.readingBackToTasks),
    ]);
  }
}

class _StatusView extends StatelessWidget {
  const _StatusView({required this.status});
  final TaskStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(padding: const EdgeInsets.all(24), children: [
      if (status == TaskStatus.done)
        Banner2(text: l10n.completed, bg: AppColors.mintSoft, fg: AppColors.mintText, icon: Icons.check_rounded)
      else
        Banner2(text: l10n.pendingApproval, bg: AppColors.pendingBg, fg: AppColors.pendingText),
      const SizedBox(height: 24),
      _BackButton(label: l10n.readingBackToTasks),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, color: AppColors.ink)),
        const SizedBox(height: 24),
        _BackButton(label: context.l10n.readingBackToTasks),
      ]);
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: AppColors.purple, width: 2),
          foregroundColor: AppColors.purpleDark,
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        onPressed: () => Navigator.of(context).maybePop(),
        child: Text(label),
      );
}
