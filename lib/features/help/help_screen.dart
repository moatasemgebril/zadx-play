import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_ext.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../services/assistant/assistant_service.dart';
import '../../shared/widgets/zad_widgets.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final steps = [
      (l10n.how1T, l10n.how1B),
      (l10n.how2T, l10n.how2B),
      (l10n.how3T, l10n.how3B),
      (l10n.how4T, l10n.how4B),
      (l10n.how5T, l10n.how5B),
    ];
    final faq = [
      (l10n.faq1Q, l10n.faq1A),
      (l10n.faq2Q, l10n.faq2A),
      (l10n.faq3Q, l10n.faq3A),
      (l10n.faq4Q, l10n.faq4A),
      (l10n.faq5Q, l10n.faq5A),
    ];
    const stepColors = [AppColors.yellow, AppColors.sky, AppColors.coral, Color(0xFF7ED9B8), Color(0xFFC4B5FD)];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.helpTitle), backgroundColor: AppColors.navy, foregroundColor: Colors.white),
      body: PatternBackground(
        tint: AppColors.pageTints['games']!,
        seed: 8,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const _AssistantCard(),
          const SizedBox(height: 14),
          ZadCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l10n.howTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: stepColors[i],
                      child: Text(Fmt.digits(i + 1, context.lang),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(steps[i].$1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        Text(steps[i].$2, style: const TextStyle(fontSize: 16, height: 1.5)),
                      ]),
                    ),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 14),
          ZadCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(l10n.faqTitle, style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final (q, a) in faq)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  shape: const Border(),
                  title: Text(q, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  children: [Text(a, style: const TextStyle(fontSize: 16, height: 1.6))],
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _AssistantCard extends ConsumerStatefulWidget {
  const _AssistantCard();

  @override
  ConsumerState<_AssistantCard> createState() => _AssistantCardState();
}

class _AssistantCardState extends ConsumerState<_AssistantCard> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = preset ?? _input.text;
    ref.read(assistantProvider.notifier).send(text, context.lang);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(assistantProvider);
    final messages = [ChatMessage(fromUser: false, text: l10n.assistantHello), ...state.messages];

    return ZadCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.purple, borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.smart_toy_rounded, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.assistantTitle, style: Theme.of(context).textTheme.titleMedium),
            Text(l10n.assistantSub, style: const TextStyle(fontSize: 15, color: AppColors.muted)),
          ]),
        ]),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 340),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: AppColors.cream, borderRadius: BorderRadius.circular(18)),
          child: ListView(shrinkWrap: true, reverse: true, children: [
            if (state.typing) _Bubble(text: l10n.typing, fromUser: false),
            if (state.error) _Bubble(text: l10n.assistantError, fromUser: false),
            for (final m in messages.reversed) _Bubble(text: m.text, fromUser: m.fromUser),
          ]),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final q in [l10n.faq1Q, l10n.faq2Q, l10n.faq3Q])
            ActionChip(label: Text(q, style: const TextStyle(fontSize: 15)), onPressed: () => _send(q)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 17),
              decoration: InputDecoration(
                labelText: l10n.askPlaceholder,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: l10n.send,
            style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
            onPressed: _send,
            icon: const Icon(Icons.send_rounded),
          ),
        ]),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromUser});
  final String text;
  final bool fromUser;

  @override
  Widget build(BuildContext context) => Align(
        alignment: fromUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: const BoxConstraints(maxWidth: 290),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fromUser ? AppColors.purple : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(text, style: TextStyle(fontSize: 16, height: 1.5, color: fromUser ? Colors.white : AppColors.ink)),
        ),
      );
}
