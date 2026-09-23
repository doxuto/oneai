import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/models/minute_models.dart';

void main() {
  group('MinuteDetail.fromJson', () {
    final j = <String, dynamic>{
      'id': 'm1',
      'title': 'T',
      'status': 'ready',
      'sourceType': 'audio',
      'tagIds': <String>[],
      'createdAt': '2026-09-23T10:00:00.000Z',
      'updatedAt': '2026-09-23T10:00:00.000Z',
      'speakers': [
        {'id': 'speaker_0', 'label': 'Ana'},
      ],
      'calendarEvents': [
        {'id': 'e1', 'title': 'Retro', 'description': 'd', 'datetime': '2026-09-25T10:00:00+07:00', 'participants': ['Ana'], 'rawText': 'retro'},
        {'id': 'e2', 'title': 'Vague', 'description': '', 'datetime': 'sometime next week', 'participants': [], 'rawText': ''},
      ],
      'availableArtifacts': ['quiz', 'calendarEvents', 'somethingNew'],
    };

    test('parses events, resolving ISO datetimes and keeping free text', () {
      final d = MinuteDetail.fromJson(j);
      expect(d.calendarEvents.length, 2);
      expect(d.calendarEvents[0].resolvedAt, DateTime.parse('2026-09-25T10:00:00+07:00'));
      expect(d.calendarEvents[0].participants, ['Ana']);
      expect(d.calendarEvents[1].resolvedAt, isNull);
      expect(d.calendarEvents[1].datetime, 'sometime next week');
    });

    test('availableArtifacts ignores kinds this build does not know', () {
      final d = MinuteDetail.fromJson(j);
      expect(d.availableArtifacts, {ArtifactKind.quiz, ArtifactKind.calendarEvents});
      expect(d.hasArtifact(ArtifactKind.quiz), isTrue);
      expect(d.hasArtifact(ArtifactKind.mindmap), isFalse);
    });

    test('source state, expiry and talk time', () {
      final d = MinuteDetail.fromJson({...j, 'sourcePath': 'p', 'sourceState': 'available', 'sourceExpiresAt': '2026-09-30T03:00:00.000Z', 'talkTime': [
        {'speakerId': 'speaker_0', 'label': 'Ana', 'seconds': 12.5, 'share': 1, 'turns': 1},
      ]});
      expect(d.canPlaySource, isTrue);
      expect(d.sourceExpiresAt, DateTime.parse('2026-09-30T03:00:00.000Z'));
      expect(d.talkTime.single.share, 1.0);
      final e = MinuteDetail.fromJson({...j, 'sourcePath': null, 'sourceState': 'expired'});
      expect(e.sourceState, SourceState.expired);
      expect(e.canPlaySource, isFalse);
      final legacy = MinuteDetail.fromJson({...j, 'sourcePath': 'p'}..remove('sourceState'));
      expect(legacy.sourceState, SourceState.available);
    });

    test('chapters.at picks the playing chapter', () {
      final c = Chapters.fromJson({'chapters': [
        {'title': 'A', 'startSeconds': 0, 'endSeconds': 10, 'summary': ''},
        {'title': 'B', 'startSeconds': 10, 'endSeconds': 20, 'summary': ''},
      ]});
      expect(c.at(0)?.title, 'A');
      expect(c.at(10)?.title, 'B');
      expect(c.at(25)?.title, 'B');
      expect(const Chapters(chapters: []).at(3), isNull);
    });

    test('older server responses without the new fields still parse', () {
      final legacy = Map<String, dynamic>.from(j)
        ..remove('calendarEvents')
        ..remove('availableArtifacts');
      final d = MinuteDetail.fromJson(legacy);
      expect(d.calendarEvents, isEmpty);
      expect(d.availableArtifacts, isEmpty);
      expect(d.speakerLabelFor('speaker_0'), 'Ana');
    });
  });
}
