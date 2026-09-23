import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/features/minutes/chat/chat_controller.dart';

/// One row of the ask-all conversation. Kept in memory for this screen only —
/// the server stores nothing for S11-01 (OQ: history sync later).
class AskAllEntry {
  const AskAllEntry({required this.role, required this.text, this.sources = const [], this.isStreaming = false, this.failed = false});
  final ChatRole role;
  final String text;
  final List<AskAllSource> sources;
  final bool isStreaming;
  final bool failed;

  AskAllEntry copyWith({String? text, List<AskAllSource>? sources, bool? isStreaming, bool? failed}) =>
      AskAllEntry(role: role, text: text ?? this.text, sources: sources ?? this.sources, isStreaming: isStreaming ?? this.isStreaming, failed: failed ?? this.failed);
}

class AskAllState {
  const AskAllState({this.messages = const [], this.sending = false, this.sendError});
  final List<AskAllEntry> messages;
  final bool sending;
  final Object? sendError;

  bool get isOutOfAiCalls => sendError is QuotaFailure;
  String? get failedQuestion {
    for (final m in messages.reversed) {
      if (m.role == ChatRole.user && m.failed) return m.text;
    }
    return null;
  }

  AskAllState copyWith({List<AskAllEntry>? messages, bool? sending, Object? sendError = _keep}) =>
      AskAllState(messages: messages ?? this.messages, sending: sending ?? this.sending, sendError: identical(sendError, _keep) ? this.sendError : sendError);
}

const Object _keep = Object();

/// `[[note:abc]]` markers are for the app, not the reader: drop them and tidy
/// the whitespace they leave behind ("Friday [[note:a]]." → "Friday.").
String stripCitations(String text) =>
    text.replaceAll(RegExp(r'\s*\[\[note:[A-Za-z0-9_-]+(?:@\d+)?\]\]'), '').replaceAll(RegExp(r' +([.,;:!?])'), r'$1').trim();

/// The last [maxTurns] finished turns, oldest first, as the server wants them.
List<Map<String, String>> historyFor(List<AskAllEntry> messages, {int maxTurns = 8}) {
  final done = [
    for (final m in messages)
      if (!m.failed && !m.isStreaming && m.text.isNotEmpty) {'role': m.role == ChatRole.user ? 'user' : 'assistant', 'text': stripCitations(m.text)},
  ];
  return done.length <= maxTurns ? done : done.sublist(done.length - maxTurns);
}

final askAllControllerProvider = NotifierProvider.autoDispose<AskAllController, AskAllState>(AskAllController.new);

class AskAllController extends Notifier<AskAllState> {
  StreamSubscription<AskAllEvent>? _sub;
  AiRepository get _ai => ref.read(aiRepositoryProvider);

  @override
  AskAllState build() {
    ref.onDispose(() => unawaited(_sub?.cancel()));
    return const AskAllState();
  }

  Future<void> send(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.sending) return;
    final history = historyFor(state.messages);
    state = state.copyWith(
      sending: true,
      sendError: null,
      messages: [...state.messages, AskAllEntry(role: ChatRole.user, text: q), const AskAllEntry(role: ChatRole.assistant, text: '', isStreaming: true)],
    );
    final botIndex = state.messages.length - 1;
    final done = Completer<void>();
    final buffer = StringBuffer();
    unawaited(_sub?.cancel());
    _sub = _ai.askAll(question: q, languageCode: ref.read(chatLanguageCodeProvider), history: history).listen(
      (ev) {
        switch (ev) {
          case AskAllDelta(:final text):
            buffer.write(text);
            _patch(botIndex, (m) => m.copyWith(text: buffer.toString()));
          case AskAllDone(:final answer):
            _patch(botIndex, (m) => m.copyWith(text: answer.answer, sources: answer.sources, isStreaming: false));
        }
      },
      onError: (Object e) {
        dev.log('askAll failed', name: 'askAll', error: e);
        _patch(botIndex - 1, (m) => m.copyWith(failed: true));
        _patch(botIndex, (m) => m.copyWith(isStreaming: false, failed: true));
        state = state.copyWith(sending: false, sendError: e);
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        _patch(botIndex, (m) => m.copyWith(isStreaming: false));
        state = state.copyWith(sending: false);
        if (!done.isCompleted) done.complete();
      },
    );
    return done.future;
  }

  /// Resends the last failed question (its rows are removed first).
  Future<void> retryLast() async {
    final q = state.failedQuestion;
    if (q == null) return;
    state = state.copyWith(messages: [for (final m in state.messages) if (!m.failed) m]);
    await send(q);
  }

  void clear() => state = const AskAllState();

  void _patch(int index, AskAllEntry Function(AskAllEntry) f) {
    if (index < 0 || index >= state.messages.length) return;
    final list = [...state.messages];
    list[index] = f(list[index]);
    state = state.copyWith(messages: list);
  }
}
