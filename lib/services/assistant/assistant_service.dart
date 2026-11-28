import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_variant.dart';
import '../../core/server_functions.dart';

@immutable
class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;

  Map<String, String> toJson() => {'role': fromUser ? 'user' : 'assistant', 'content': text};
}

/// AI help for parents. The app never holds an AI API key: questions go to the
/// `askAssistant` Cloud Function, which calls the Claude API with a system
/// prompt about Zad X and enforces plan limits (Basic = limited, Plus = unlimited).
///
/// Hidden in every build today (owner decision 2026-11-28: zero cost, no Cloud Functions, so no
/// place for the key): `FeatureFlags.assistant` is off, no screen offers it, and [ask] fails with
/// [ServerFunctionsDisabled] without any network call.
class AssistantService {
  AssistantService({ServerCalls? server}) : _server = server ?? serverCallsFor();
  final ServerCalls _server;

  Future<String> ask(String question, {required String language, required List<ChatMessage> history}) async {
    final res = await _server.call(
      'askAssistant',
      {
        'question': question,
        'language': language,
        // Zad X Kids gets a system prompt with no religious content (backend/functions/src/index.ts).
        'variant': appVariant.name,
        'history': history.takeLast(8).map((m) => m.toJson()).toList(),
      },
      const Duration(seconds: 30),
    );
    return (res! as Map)['answer'] as String;
  }
}

extension<T> on List<T> {
  Iterable<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}

final assistantServiceProvider = Provider<AssistantService>((ref) => AssistantService(server: ref.watch(serverCallsProvider)));

class AssistantState {
  const AssistantState({this.messages = const [], this.typing = false, this.error = false});
  final List<ChatMessage> messages;
  final bool typing;
  final bool error;
}

class AssistantController extends Notifier<AssistantState> {
  @override
  AssistantState build() => const AssistantState();

  Future<void> send(String text, String language) async {
    final q = text.trim();
    if (q.isEmpty || state.typing) return;
    final history = [...state.messages, ChatMessage(fromUser: true, text: q)];
    state = AssistantState(messages: history, typing: true);
    try {
      final answer = await ref.read(assistantServiceProvider).ask(q, language: language, history: state.messages);
      state = AssistantState(messages: [...history, ChatMessage(fromUser: false, text: answer)]);
    } catch (e) {
      debugPrint('assistant failed: $e');
      state = AssistantState(messages: history, error: true);
    }
  }
}

final assistantProvider = NotifierProvider<AssistantController, AssistantState>(AssistantController.new);
