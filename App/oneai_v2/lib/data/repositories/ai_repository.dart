import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/models/ai_models.dart';

/// One event of a streaming chat: either a partial delta or the final answer.
sealed class ChatEvent {
  const ChatEvent();
}

final class ChatDelta extends ChatEvent {
  const ChatDelta(this.text);
  final String text;
}

final class ChatDone extends ChatEvent {
  const ChatDone(this.answer);
  final ChatAnswer answer;
}

class AiRepository {
  AiRepository({required FunctionsClient functions}) : _fns = functions;
  final FunctionsClient _fns;

  /// Streams deltas as the model produces them, then the persisted answer.
  Stream<ChatEvent> chat({required String minuteId, required String question, String languageCode = 'en'}) async* {
    await for (final ev in _fns.stream('chat', {'minuteId': minuteId, 'question': question, 'languageCode': languageCode})) {
      if (ev is Map) {
        final m = Map<String, dynamic>.from(ev);
        if (m['delta'] is String) {
          yield ChatDelta(m['delta'] as String);
        } else if (m.containsKey('answer')) {
          yield ChatDone(ChatAnswer.fromJson(m));
        }
      }
    }
  }

  Future<ChatPage> history(String minuteId, {int limit = 50, String? cursor}) async =>
      ChatPage.fromJson(await _fns.call('listChatMessages', {'minuteId': minuteId, 'limit': limit, if (cursor != null) 'cursor': cursor}));

  Map<String, Object?> _gen(String minuteId, String languageCode, bool force) =>
      {'minuteId': minuteId, 'languageCode': languageCode, 'force': force};

  Future<Generated<ShortQuestions>> shortQuestions(String minuteId, {String languageCode = 'en', bool force = false}) async =>
      Generated.fromJson(await _fns.call('generateShortQuestions', _gen(minuteId, languageCode, force)), ShortQuestions.fromJson);

  Future<Generated<Quiz>> quiz(String minuteId, {String languageCode = 'en', bool force = false}) async =>
      Generated.fromJson(await _fns.call('generateQuiz', _gen(minuteId, languageCode, force)), Quiz.fromJson);

  Future<Generated<Flashcards>> flashcards(String minuteId, {String languageCode = 'en', bool force = false}) async =>
      Generated.fromJson(await _fns.call('generateFlashcards', _gen(minuteId, languageCode, force)), Flashcards.fromJson);

  Future<Generated<Mindmap>> mindmap(String minuteId, {String languageCode = 'en', bool force = false}) async =>
      Generated.fromJson(await _fns.call('generateMindmap', _gen(minuteId, languageCode, force)), Mindmap.fromJson);

  /// Events are already extracted at summarise time (`MinuteDetail.calendarEvents`);
  /// call this only to regenerate, e.g. in another language. [timezone] is an
  /// IANA name; omitted → the zone sent at startTranscription.
  Future<Generated<CalendarEvents>> calendarEvents(String minuteId, {String languageCode = 'en', bool force = false, String? timezone}) async =>
      Generated.fromJson(
        await _fns.call('generateCalendarEvents', {..._gen(minuteId, languageCode, force), if (timezone != null) 'timezone': timezone}),
        CalendarEvents.fromJson,
      );

  /// Action items + decisions (meetings). Same timezone rule as calendar events.
  Future<Generated<ActionItems>> actionItems(String minuteId, {String languageCode = 'en', bool force = false, String? timezone}) async =>
      Generated.fromJson(
        await _fns.call('generateActionItems', {..._gen(minuteId, languageCode, force), if (timezone != null) 'timezone': timezone}),
        ActionItems.fromJson,
      );

  /// Glossary of jargon and named concepts (lectures).
  Future<Generated<KeyTerms>> keyTerms(String minuteId, {String languageCode = 'en', bool force = false}) async =>
      Generated.fromJson(await _fns.call('generateKeyTerms', _gen(minuteId, languageCode, force)), KeyTerms.fromJson);

  /// Topic chapters with timestamps; refused for PDFs (`PreconditionFailure`, reason `noTimeline`).
  Future<Generated<Chapters>> chapters(String minuteId, {String languageCode = 'en', bool force = false}) async =>
      Generated.fromJson(await _fns.call('generateChapters', _gen(minuteId, languageCode, force)), Chapters.fromJson);

  Future<Generated<Speakers>> mapSpeakers(String minuteId, {bool force = false}) async =>
      Generated.fromJson(await _fns.call('mapSpeakers', {'minuteId': minuteId, 'force': force}), Speakers.fromJson);

  Future<Speakers> renameSpeaker(String minuteId, {required String speakerId, required String name}) async =>
      Generated.fromJson(await _fns.call('renameSpeaker', {'minuteId': minuteId, 'speakerId': speakerId, 'name': name}), Speakers.fromJson).data;
}
