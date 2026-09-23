import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/features/settings/language_settings.dart';

// ---- State ----

/// One row in the chat list. Server-persisted messages carry their Firestore
/// id; the pair being sent carries a local id until `ChatDone` arrives.
class ChatEntry {
  const ChatEntry({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.isStreaming = false,
    this.failed = false,
  });

  factory ChatEntry.fromMessage(ChatMessage m) =>
      ChatEntry(id: m.id, role: m.role, text: m.text, createdAt: m.createdAt);

  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;

  /// Assistant row still receiving deltas.
  final bool isStreaming;

  /// The send failed; the user row stays so "retry" can resend it.
  final bool failed;

  ChatEntry copyWith({String? id, String? text, bool? isStreaming, bool? failed}) => ChatEntry(
        id: id ?? this.id,
        role: role,
        text: text ?? this.text,
        createdAt: createdAt,
        isStreaming: isStreaming ?? this.isStreaming,
        failed: failed ?? this.failed,
      );
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.loadingHistory = false,
    this.historyError,
    this.olderCursor,
    this.sending = false,
    this.sendError,
  });

  /// Oldest first, so a reversed ListView shows the newest at the bottom.
  final List<ChatEntry> messages;
  final bool loadingHistory;
  final Object? historyError;

  /// Cursor for the page *before* the oldest loaded message; null = no more.
  final String? olderCursor;

  /// A question is in flight (streaming or waiting). Input is disabled.
  final bool sending;

  /// The last send's failure, cleared on the next send. [QuotaFailure] here
  /// means the per-day AI-call cap, not transcription credits.
  final Object? sendError;

  bool get hasOlder => olderCursor != null;
  bool get isOutOfAiCalls => sendError is QuotaFailure;

  /// The failed question to resend, if the last send failed.
  ChatEntry? get failedQuestion {
    for (final m in messages.reversed) {
      if (m.role == ChatRole.user && m.failed) return m;
    }
    return null;
  }

  ChatState copyWith({
    List<ChatEntry>? messages,
    bool? loadingHistory,
    Object? historyError = _keep,
    String? olderCursor = _keepStr,
    bool? sending,
    Object? sendError = _keep,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        loadingHistory: loadingHistory ?? this.loadingHistory,
        historyError: identical(historyError, _keep) ? this.historyError : historyError,
        olderCursor: identical(olderCursor, _keepStr) ? this.olderCursor : olderCursor,
        sending: sending ?? this.sending,
        sendError: identical(sendError, _keep) ? this.sendError : sendError,
      );
}

const Object _keep = Object();
const String _keepStr = '\u0000keep';

// ---- Wiring ----

/// Language the assistant answers in: the user's summary language.
final chatLanguageCodeProvider = Provider<String>((ref) => ref.watch(aiLanguageCodeProvider));

final chatControllerProvider =
    NotifierProvider.autoDispose.family<ChatController, ChatState, String>(ChatController.new);

// ---- Controller ----

class ChatController extends Notifier<ChatState> {
  ChatController(this.minuteId);

  final String minuteId;
  static const pageSize = 50;

  StreamSubscription<ChatEvent>? _sub;
  int _localSeq = 0;

  AiRepository get _ai => ref.read(aiRepositoryProvider);

  @override
  ChatState build() {
    ref.onDispose(() => unawaited(_sub?.cancel()));
    unawaited(Future<void>.microtask(loadHistory));
    return const ChatState(loadingHistory: true);
  }

  /// First page (the newest [pageSize] messages).
  Future<void> loadHistory() async {
    state = state.copyWith(loadingHistory: true, historyError: null);
    try {
      final page = await _ai.history(minuteId, limit: pageSize);
      state = state.copyWith(
        messages: _oldestFirst(page.items),
        olderCursor: page.nextCursor,
        loadingHistory: false,
      );
    } on Object catch (e) {
      state = state.copyWith(loadingHistory: false, historyError: e);
    }
  }

  /// Prepends the previous page. No-op while loading or when exhausted.
  Future<void> loadOlder() async {
    final cursor = state.olderCursor;
    if (cursor == null || state.loadingHistory) return;
    state = state.copyWith(loadingHistory: true);
    try {
      final page = await _ai.history(minuteId, limit: pageSize, cursor: cursor);
      state = state.copyWith(
        messages: [..._oldestFirst(page.items), ...state.messages],
        olderCursor: page.nextCursor,
        loadingHistory: false,
      );
    } on Object catch (e) {
      state = state.copyWith(loadingHistory: false, historyError: e);
    }
  }

  /// Appends the question and a streaming assistant row, then fills the row
  /// delta by delta. Ignored while another send is in flight or when blank.
  Future<void> send(String question) async {
    final q = question.trim();
    if (q.isEmpty || state.sending) return;

    final now = DateTime.now();
    final userId = 'local-${_localSeq++}';
    final botId = 'local-${_localSeq++}';
    state = state.copyWith(
      sending: true,
      sendError: null,
      messages: [
        ...state.messages,
        ChatEntry(id: userId, role: ChatRole.user, text: q, createdAt: now),
        ChatEntry(id: botId, role: ChatRole.assistant, text: '', createdAt: now, isStreaming: true),
      ],
    );

    final done = Completer<void>();
    var buffer = StringBuffer();
    unawaited(_sub?.cancel());
    _sub = _ai.chat(minuteId: minuteId, question: q, languageCode: ref.read(chatLanguageCodeProvider)).listen(
      (ev) {
        switch (ev) {
          case ChatDelta(:final text):
            buffer.write(text);
            _patch(botId, (m) => m.copyWith(text: buffer.toString()));
          case ChatDone(:final answer):
            // The server's text wins (it may have trimmed or post-processed).
            buffer = StringBuffer(answer.answer);
            _patch(botId, (m) => m.copyWith(id: answer.messageId.isEmpty ? m.id : answer.messageId, text: answer.answer, isStreaming: false));
        }
      },
      onError: (Object e) {
        dev.log('chat failed', name: 'chat', error: e);
        _fail(userId, botId, e);
        if (!done.isCompleted) done.complete();
      },
      onDone: () {
        final bot = _find(botId);
        if (bot != null && bot.isStreaming) {
          // Stream closed without ChatDone — treat as a transient failure so
          // the user can retry rather than staring at a half answer.
          _fail(userId, botId, const TransientFailure('Answer stream ended early'));
        } else {
          state = state.copyWith(sending: false);
        }
        if (!done.isCompleted) done.complete();
      },
      cancelOnError: true,
    );
    return done.future;
  }

  /// Resends the last failed question (removing its failed rows first).
  Future<void> retryLast() async {
    final failed = state.failedQuestion;
    if (failed == null || state.sending) return;
    state = state.copyWith(messages: state.messages.where((m) => !m.failed).toList());
    await send(failed.text);
  }

  void clearError() => state = state.copyWith(sendError: null);

  // ---- Helpers ----

  static List<ChatEntry> _oldestFirst(List<ChatMessage> items) {
    final out = items.map(ChatEntry.fromMessage).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  ChatEntry? _find(String id) {
    for (final m in state.messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  void _patch(String id, ChatEntry Function(ChatEntry) f) {
    state = state.copyWith(messages: [for (final m in state.messages) m.id == id ? f(m) : m]);
  }

  void _fail(String userId, String botId, Object error) {
    state = state.copyWith(
      sending: false,
      sendError: error,
      messages: [
        for (final m in state.messages)
          if (m.id == botId)
            // Drop the empty streaming row; keep a partial answer, marked failed.
            ...(m.text.isEmpty ? const <ChatEntry>[] : [m.copyWith(isStreaming: false, failed: true)])
          else if (m.id == userId)
            m.copyWith(failed: true)
          else
            m,
      ],
    );
  }
}
