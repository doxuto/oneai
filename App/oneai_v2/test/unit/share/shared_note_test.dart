import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/repositories/shares_repository.dart';

void main() {
  test('SharedNote parses the sharePage?format=json payload', () {
    final n = SharedNote.fromJson({
      'token': 'abc',
      'title': 'Standup',
      'iconEmoji': '📝',
      'createdAt': '2026-09-24',
      'sourceType': 'audio',
      'summary': {'title': 'S', 'text': 'We synced.', 'icon': null, 'sections': [{'title': 'Decisions', 'bullets': ['• Ship Friday']}]},
      'transcript': {'durationSeconds': 4, 'languageCode': 'en', 'languageProbability': 0.9, 'text': 'hi', 'segments': [{'startSeconds': 0, 'endSeconds': 1, 'text': 'hi', 'speakerId': 'speaker_0', 'speakerLabel': 'Speaker 1'}]},
      'speakers': [{'id': 'speaker_0', 'label': 'Ana'}],
      'pdfUrl': 'https://x.test/s?t=abc&format=pdf',
    });
    expect(n.sourceType, SourceType.audio);
    expect(n.summary?.sections.single.bullets, ['• Ship Friday']);
    expect(n.transcript?.segments.single.text, 'hi');
    expect(n.speakerLabelFor('speaker_0'), 'Ana');
    expect(n.speakerLabelFor('speaker_9'), 'speaker_9');
    expect(n.pdfUrl, endsWith('format=pdf'));
  });

  test('summary-only share has no transcript', () {
    final n = SharedNote.fromJson({'token': 'abc', 'title': 'T', 'summary': null, 'transcript': null, 'speakers': [], 'pdfUrl': ''});
    expect(n.transcript, isNull);
    expect(n.summary, isNull);
  });
}
