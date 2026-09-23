import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/minutes/share/export.dart';

MinuteDetail detail() => MinuteDetail(
      summaryInfo: MinuteSummary(id: 'm1', title: 'Standup', iconEmoji: null, sourceType: SourceType.audio, contentKind: null, status: MinuteStatus.ready, durationSeconds: 95, tagIds: const [], createdAt: DateTime(2026, 9, 23, 10), updatedAt: DateTime(2026, 9, 23, 10)),
      summary: const Summary(title: 'Standup', text: 't', icon: null, sections: [SummarySection(title: 'Overview', bullets: ['• We synced.', '    ◦ API done'])]),
      transcript: const Transcript(durationSeconds: 95, languageCode: 'eng', languageProbability: null, text: 'x', segments: [
        TranscriptSegment(startSeconds: 0, endSeconds: 4, text: 'Hi', speakerId: 'speaker_0', speakerLabel: 'Speaker 1'),
        TranscriptSegment(startSeconds: 65, endSeconds: 70, text: 'Bye', speakerId: 'speaker_1', speakerLabel: 'Speaker 2'),
      ]),
      sourcePath: 'p',
      speakers: const [Speaker(id: 'speaker_0', label: 'Ana')],
      failure: null,
      description: null,
      keywords: const [],
      summaryLanguage: null,
      calendarEvents: const [CalendarEvent(id: 'e1', title: 'Retro', description: '', datetime: '2026-09-25T10:00:00+07:00', participants: ['Ana'], rawText: '')],
    );

void main() {
  test('notes markdown: title, sections with nested bullets, action items, events, chapters', () {
    final md = MinuteExport.notesMarkdown(
      detail(),
      actionItems: const ActionItems(items: [ActionItem(id: 'a1', text: 'Send deck', owner: 'Ana', due: '2026-09-26', quote: '')], decisions: ['Ship Friday']),
      chapters: const Chapters(chapters: [Chapter(title: 'Intro', startSeconds: 0, endSeconds: 60, summary: '')]),
    );
    expect(md, contains('# Standup'));
    expect(md, contains('## Overview\n\n- We synced.\n  - API done'));
    expect(md, contains('- [ ] Send deck (Ana, 2026-09-26)'));
    expect(md, contains('## Decisions\n\n- Ship Friday'));
    expect(md, contains('- Retro — 2026-09-25T10:00:00+07:00 (Ana)'));
    expect(md, contains('- 0:00 Intro'));
  });

  test('notes markdown without artifacts has no empty headings', () {
    final md = MinuteExport.notesMarkdown(detail());
    expect(md, isNot(contains('Action items')));
    expect(md, isNot(contains('Chapters')));
  });

  test('transcript text uses renamed speakers and clock stamps', () {
    final t = MinuteExport.transcriptText(detail());
    expect(t, contains('[0:00] Ana: Hi'));
    expect(t, contains('[1:05] Speaker 2: Bye'));
  });

  test('pdf renders without throwing and is non-trivial', () async {
    final bytes = await MinuteExport.pdf('Standup', MinuteExport.notesMarkdown(detail()));
    expect(bytes.length, greaterThan(500));
  });
}
