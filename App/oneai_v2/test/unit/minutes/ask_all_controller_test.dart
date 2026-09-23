import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/features/minutes/ask/ask_all_controller.dart';

void main() {
  test('stripCitations removes [[note:id]] markers and the space before punctuation', () {
    expect(stripCitations('We ship Friday [[note:abc]]. Ana owns QA [[note:x_1]] [[note:abc@12]].'), 'We ship Friday. Ana owns QA.');
    expect(stripCitations('plain text'), 'plain text');
    expect(stripCitations('[[note:a]]'), '');
  });

  test('historyFor keeps finished turns only, oldest first, capped at the last N', () {
    final msgs = [
      const AskAllEntry(role: ChatRole.user, text: 'q1'),
      const AskAllEntry(role: ChatRole.assistant, text: 'a1 [[note:z]]'),
      const AskAllEntry(role: ChatRole.user, text: 'failed', failed: true),
      const AskAllEntry(role: ChatRole.assistant, text: '', failed: true),
      const AskAllEntry(role: ChatRole.user, text: 'q2'),
      const AskAllEntry(role: ChatRole.assistant, text: 'streaming', isStreaming: true),
    ];
    expect(historyFor(msgs), [
      {'role': 'user', 'text': 'q1'},
      {'role': 'assistant', 'text': 'a1'},
      {'role': 'user', 'text': 'q2'},
    ]);
    expect(historyFor(msgs, maxTurns: 2), [
      {'role': 'assistant', 'text': 'a1'},
      {'role': 'user', 'text': 'q2'},
    ]);
  });

  test('AskAllState.failedQuestion is the last failed user row', () {
    const s = AskAllState(messages: [AskAllEntry(role: ChatRole.user, text: 'x', failed: true), AskAllEntry(role: ChatRole.assistant, text: '', failed: true)]);
    expect(s.failedQuestion, 'x');
    expect(const AskAllState().failedQuestion, isNull);
  });

  test('AskAllAnswer / SearchHit parse the callable payloads', () {
    final a = AskAllAnswer.fromJson({'answer': 'Friday [[note:m1@45]].', 'sources': [{'minuteId': 'm1', 'title': 'Standup', 'iconEmoji': '📝', 'createdAt': '2026-09-18T09:00:00.000Z', 'startSeconds': 45}]});
    expect(a.sources.single.minuteId, 'm1');
    expect(a.sources.single.startSeconds, 45);
    expect(stripCitations('Friday [[note:m1@45]].'), 'Friday.');
    expect(a.sources.single.createdAt?.year, 2026);
    final h = SearchHit.fromJson({'minuteId': 'm2', 'title': 'T', 'score': 0.91});
    expect(h.score, 0.91);
  });
}
