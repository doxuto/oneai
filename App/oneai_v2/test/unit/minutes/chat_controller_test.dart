import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';
import 'package:one_ai/features/minutes/chat/chat_controller.dart';

ChatMessage msg(String id, ChatRole role, String text, int minute) =>
    ChatMessage(id: id, role: role, text: text, createdAt: DateTime(2026, 9, 23, 10, minute));

class FakeAi implements AiRepository {
  final calls = <String>[];
  final pages = <String?, ChatPage>{};
  Object? historyError;
  var chat = StreamController<ChatEvent>();

  @override
  Future<ChatPage> history(String minuteId, {int limit = 50, String? cursor}) async {
    calls.add('history:$cursor');
    if (historyError != null) throw historyError!;
    return pages[cursor] ?? const ChatPage(items: [], nextCursor: null);
  }

  @override
  Stream<ChatEvent> chat({required String minuteId, required String question, String languageCode = 'en'}) {
    calls.add('chat:$question:$languageCode');
    return chat.stream;
  }

  @override
  Future<Generated<ShortQuestions>> shortQuestions(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<Quiz>> quiz(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<Flashcards>> flashcards(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<Mindmap>> mindmap(String minuteId, {String languageCode = 'en', bool force = false}) => throw UnimplementedError();
  @override
  Future<Generated<CalendarEvents>> calendarEvents(String minuteId, {String languageCode = 'en', bool force = false, String? timezone}) => throw UnimplementedError();
  @override
  Future<Generated<Speakers>> mapSpeakers(String minuteId, {bool force = false}) => throw UnimplementedError();
  @override
  Future<Speakers> renameSpeaker(String minuteId, {required String speakerId, required String name}) => throw UnimplementedError();
}

class Harness {
  Harness({String lang = 'en'}) {
    container = ProviderContainer.test(overrides: [
      aiRepositoryProvider.overrideWithValue(ai),
      chatLanguageCodeProvider.overrideWithValue(lang),
    ]);
    container.listen(chatControllerProvider('m1'), (_, __) {});
  }
  final ai = FakeAi();
  late final ProviderContainer container;
  ChatState get state => container.read(chatControllerProvider('m1'));
  ChatController get ctl => container.read(chatControllerProvider('m1').notifier);
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('history', () {
    test('loads the newest page on build, oldest first', () async {
      final h = Harness();
      h.ai.pages[null] = ChatPage(items: [msg('b', ChatRole.assistant, 'A2', 2), msg('a', ChatRole.user, 'Q1', 1)], nextCursor: 'c1');
      expect(h.state.loadingHistory, isTrue);
      await settle();
      expect(h.state.loadingHistory, isFalse);
      expect(h.state.messages.map((m) => m.id), ['a', 'b']);
      expect(h.state.hasOlder, isTrue);
    });

    test('loadOlder prepends and stops at the end', () async {
      final h = Harness();
      h.ai.pages[null] = ChatPage(items: [msg('c', ChatRole.user, 'Q3', 3)], nextCursor: 'c1');
      h.ai.pages['c1'] = ChatPage(items: [msg('b', ChatRole.assistant, 'A', 2), msg('a', ChatRole.user, 'Q', 1)], nextCursor: null);
      await settle();
      await h.ctl.loadOlder();
      expect(h.state.messages.map((m) => m.id), ['a', 'b', 'c']);
      expect(h.state.hasOlder, isFalse);
      await h.ctl.loadOlder();
      expect(h.ai.calls.where((c) => c.startsWith('history:')).length, 2);
    });

    test('history failure is exposed and retryable', () async {
      final h = Harness()..ai.historyError = const TransientFailure('x');
      await settle();
      expect(h.state.historyError, isA<TransientFailure>());
      h.ai.historyError = null;
      await h.ctl.loadHistory();
      expect(h.state.historyError, isNull);
    });
  });

  group('send', () {
    test('streams deltas into the assistant row, then adopts the server text and id', () async {
      final h = Harness(lang: 'vi');
      await settle();
      final sending = h.ctl.send('  what happened?  ');
      await settle();
      expect(h.state.sending, isTrue);
      expect(h.state.messages.length, 2);
      expect(h.state.messages[0].text, 'what happened?');
      expect(h.state.messages[1].isStreaming, isTrue);
      expect(h.ai.calls.last, 'chat:what happened?:vi');

      h.ai.chat.add(const ChatDelta('Hel'));
      h.ai.chat.add(const ChatDelta('lo'));
      await settle();
      expect(h.state.messages[1].text, 'Hello');

      h.ai.chat.add(const ChatDone(ChatAnswer(answer: 'Hello.', messageId: 'srv-1')));
      await h.ai.chat.close();
      await sending;
      expect(h.state.sending, isFalse);
      expect(h.state.messages[1].id, 'srv-1');
      expect(h.state.messages[1].text, 'Hello.');
      expect(h.state.messages[1].isStreaming, isFalse);
      expect(h.state.sendError, isNull);
    });

    test('blank question and re-entrant send are ignored', () async {
      final h = Harness();
      await settle();
      await h.ctl.send('   ');
      expect(h.state.messages, isEmpty);
      final first = h.ctl.send('a');
      await settle();
      await h.ctl.send('b');
      expect(h.ai.calls.where((c) => c.startsWith('chat:')).length, 1);
      await h.ai.chat.close();
      await first;
    });

    test('error before any delta: keeps the question marked failed, drops the empty row', () async {
      final h = Harness();
      await settle();
      final sending = h.ctl.send('q');
      await settle();
      h.ai.chat.addError(const QuotaFailure('ai cap', null));
      await sending;
      expect(h.state.sending, isFalse);
      expect(h.state.isOutOfAiCalls, isTrue);
      expect(h.state.messages.length, 1);
      expect(h.state.messages.single.failed, isTrue);
      expect(h.state.failedQuestion?.text, 'q');
    });

    test('error mid-stream keeps the partial answer, marked failed', () async {
      final h = Harness();
      await settle();
      final sending = h.ctl.send('q');
      await settle();
      h.ai.chat.add(const ChatDelta('partial'));
      await settle();
      h.ai.chat.addError(const TransientFailure('cut'));
      await sending;
      expect(h.state.messages.length, 2);
      expect(h.state.messages[1].text, 'partial');
      expect(h.state.messages[1].failed, isTrue);
      expect(h.state.messages[1].isStreaming, isFalse);
    });

    test('stream closing without ChatDone counts as a transient failure', () async {
      final h = Harness();
      await settle();
      final sending = h.ctl.send('q');
      await settle();
      await h.ai.chat.close();
      await sending;
      expect(h.state.sendError, isA<TransientFailure>());
      expect(h.state.sending, isFalse);
    });

    test('retryLast removes the failed rows and resends the same text', () async {
      final h = Harness();
      await settle();
      final s1 = h.ctl.send('again?');
      await settle();
      h.ai.chat.addError(const TransientFailure('x'));
      await s1;
      h.ai.chat = StreamController();
      final s2 = h.ctl.retryLast();
      await settle();
      expect(h.state.messages.length, 2);
      expect(h.state.messages[0].failed, isFalse);
      expect(h.state.sendError, isNull);
      h.ai.chat.add(const ChatDone(ChatAnswer(answer: 'ok', messageId: 'm')));
      await h.ai.chat.close();
      await s2;
      expect(h.ai.calls.where((c) => c == 'chat:again?:en').length, 2);
      expect(h.state.messages[1].text, 'ok');
    });

    test('retryLast is a no-op when nothing failed', () async {
      final h = Harness();
      await settle();
      await h.ctl.retryLast();
      expect(h.ai.calls.where((c) => c.startsWith('chat:')), isEmpty);
    });
  });

  test('disposing cancels the chat subscription', () async {
    final h = Harness();
    await settle();
    unawaited(h.ctl.send('q'));
    await settle();
    expect(h.ai.chat.hasListener, isTrue);
    h.container.dispose();
    await settle();
    expect(h.ai.chat.hasListener, isFalse);
  });
}
