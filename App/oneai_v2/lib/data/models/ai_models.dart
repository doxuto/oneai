import 'package:one_ai/data/firebase/json_read.dart';
import 'package:one_ai/data/models/minute_models.dart' show CalendarEvent, Speaker;

enum ChatRole { user, assistant }

class ChatMessage {
  const ChatMessage({required this.id, required this.role, required this.text, required this.createdAt});
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: readRequiredString(j, 'id'),
        role: readString(j, 'role') == 'assistant' ? ChatRole.assistant : ChatRole.user,
        text: readString(j, 'text') ?? '',
        createdAt: readDateTime(j, 'createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
  final String id;
  final ChatRole role;
  final String text;
  final DateTime createdAt;
}

class ChatPage {
  const ChatPage({required this.items, required this.nextCursor});
  factory ChatPage.fromJson(Map<String, dynamic> j) => ChatPage(
        items: readObjectList(j, 'items').map(ChatMessage.fromJson).toList(),
        nextCursor: readString(j, 'nextCursor'),
      );
  final List<ChatMessage> items;
  final String? nextCursor;
}

class ChatAnswer {
  const ChatAnswer({required this.answer, required this.messageId});
  factory ChatAnswer.fromJson(Map<String, dynamic> j) =>
      ChatAnswer(answer: readString(j, 'answer') ?? '', messageId: readString(j, 'messageId') ?? '');
  final String answer;
  final String messageId;
}

/// Every generate* call returns `{data, cached}`.
class Generated<T> {
  const Generated({required this.data, required this.cached});
  final T data;
  final bool cached;

  static Generated<T> fromJson<T>(Map<String, dynamic> j, T Function(Map<String, dynamic>) parse) =>
      Generated(data: parse(readObject(j, 'data') ?? const <String, dynamic>{}), cached: readBool(j, 'cached'));
}

class QuizItem {
  const QuizItem({required this.question, required this.options, required this.answerIndex});
  factory QuizItem.fromJson(Map<String, dynamic> j) => QuizItem(
        question: readString(j, 'question') ?? '',
        options: readStringList(j, 'options'),
        answerIndex: readInt(j, 'answerIndex') ?? 0,
      );
  final String question;
  final List<String> options;
  final int answerIndex;
  bool get isTrueFalse => options.length == 2;
}

class Quiz {
  const Quiz({required this.items});
  factory Quiz.fromJson(Map<String, dynamic> j) => Quiz(items: readObjectList(j, 'items').map(QuizItem.fromJson).toList());
  final List<QuizItem> items;
}

class Flashcard {
  const Flashcard({required this.question, required this.answer});
  factory Flashcard.fromJson(Map<String, dynamic> j) =>
      Flashcard(question: readString(j, 'question') ?? '', answer: readString(j, 'answer') ?? '');
  final String question;
  final String answer;
}

class Flashcards {
  const Flashcards({required this.items});
  factory Flashcards.fromJson(Map<String, dynamic> j) => Flashcards(items: readObjectList(j, 'items').map(Flashcard.fromJson).toList());
  final List<Flashcard> items;
}

class MindmapNode {
  const MindmapNode({required this.id, required this.title, required this.icon, required this.children});
  factory MindmapNode.fromJson(Map<String, dynamic> j) => MindmapNode(
        id: readString(j, 'id') ?? '',
        title: readString(j, 'title') ?? '',
        icon: readString(j, 'icon'),
        children: readObjectList(j, 'children').map(MindmapNode.fromJson).toList(),
      );
  final String id;
  final String title;
  /// Only the root carries an icon.
  final String? icon;
  final List<MindmapNode> children;
}

class Mindmap {
  const Mindmap({required this.root});
  factory Mindmap.fromJson(Map<String, dynamic> j) =>
      Mindmap(root: MindmapNode.fromJson(readObject(j, 'root') ?? const <String, dynamic>{}));
  final MindmapNode root;
}

class ShortQuestions {
  const ShortQuestions({required this.questions});
  factory ShortQuestions.fromJson(Map<String, dynamic> j) => ShortQuestions(questions: readStringList(j, 'questions'));
  final List<String> questions;
}

class Speakers {
  const Speakers({required this.speakers});
  factory Speakers.fromJson(Map<String, dynamic> j) => Speakers(speakers: readObjectList(j, 'speakers').map(Speaker.fromJson).toList());
  final List<Speaker> speakers;
}

class CalendarEvents {
  const CalendarEvents({required this.events});
  factory CalendarEvents.fromJson(Map<String, dynamic> j) =>
      CalendarEvents(events: readObjectList(j, 'events').map(CalendarEvent.fromJson).toList());
  final List<CalendarEvent> events;
}

class ActionItem {
  const ActionItem({required this.id, required this.text, required this.owner, required this.due, required this.quote, this.done = false});
  factory ActionItem.fromJson(Map<String, dynamic> j) => ActionItem(
        id: readString(j, 'id') ?? '',
        text: readString(j, 'text') ?? '',
        owner: readString(j, 'owner'),
        due: readString(j, 'due'),
        quote: readString(j, 'quote') ?? '',
        done: readBool(j, 'done'),
      );
  final String id;
  final String text;
  final String? owner;
  /// ISO-8601 date when the model could resolve one.
  final String? due;
  final String quote;
  /// Ticked by the user; stored server-side (setActionItemDone).
  final bool done;
  DateTime? get dueAt => due == null ? null : DateTime.tryParse(due!);
  ActionItem copyWith({bool? done}) => ActionItem(id: id, text: text, owner: owner, due: due, quote: quote, done: done ?? this.done);
}

class ActionItems {
  const ActionItems({required this.items, required this.decisions});
  factory ActionItems.fromJson(Map<String, dynamic> j) => ActionItems(
        items: readObjectList(j, 'items').map(ActionItem.fromJson).toList(),
        decisions: readStringList(j, 'decisions'),
      );
  final List<ActionItem> items;
  final List<String> decisions;
  ActionItems withDone(String itemId, bool done) =>
      ActionItems(items: [for (final it in items) it.id == itemId ? it.copyWith(done: done) : it], decisions: decisions);
}

/// S11-04 result of `translate`.
class Translation {
  const Translation({required this.part, required this.languageCode, required this.text, required this.cached});
  factory Translation.fromJson(Map<String, dynamic> j) => Translation(
        part: readString(j, 'part') ?? 'summary',
        languageCode: readString(j, 'languageCode') ?? '',
        text: readString(j, 'text') ?? '',
        cached: readBool(j, 'cached'),
      );
  final String part;
  final String languageCode;
  final String text;
  final bool cached;
}

class KeyTerm {
  const KeyTerm({required this.term, required this.definition, required this.quote});
  factory KeyTerm.fromJson(Map<String, dynamic> j) =>
      KeyTerm(term: readString(j, 'term') ?? '', definition: readString(j, 'definition') ?? '', quote: readString(j, 'quote') ?? '');
  final String term;
  final String definition;
  final String quote;
}

class KeyTerms {
  const KeyTerms({required this.terms});
  factory KeyTerms.fromJson(Map<String, dynamic> j) => KeyTerms(terms: readObjectList(j, 'terms').map(KeyTerm.fromJson).toList());
  final List<KeyTerm> terms;
}

class Chapter {
  const Chapter({required this.title, required this.startSeconds, required this.endSeconds, required this.summary});
  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        title: readString(j, 'title') ?? '',
        startSeconds: readDouble(j, 'startSeconds') ?? 0,
        endSeconds: readDouble(j, 'endSeconds') ?? 0,
        summary: readString(j, 'summary') ?? '',
      );
  final String title;
  final double startSeconds;
  final double endSeconds;
  final String summary;
}

class Chapters {
  const Chapters({required this.chapters});
  factory Chapters.fromJson(Map<String, dynamic> j) => Chapters(chapters: readObjectList(j, 'chapters').map(Chapter.fromJson).toList());
  final List<Chapter> chapters;

  /// The chapter playing at [seconds], for the "now playing" highlight.
  Chapter? at(double seconds) {
    for (final c in chapters) {
      if (seconds >= c.startSeconds && seconds < c.endSeconds) return c;
    }
    return chapters.isNotEmpty && seconds >= chapters.last.startSeconds ? chapters.last : null;
  }
}

// ---- S11-01/02: ask across notes, semantic search ----

/// A note the ask-all answer cited. The answer text carries `[[note:id]]`
/// markers in the same order; the app strips them and shows these as chips.
class AskAllSource {
  const AskAllSource({required this.minuteId, required this.title, this.iconEmoji, this.createdAt, this.startSeconds});
  factory AskAllSource.fromJson(Map<String, dynamic> j) => AskAllSource(
        minuteId: readRequiredString(j, 'minuteId'),
        title: readString(j, 'title') ?? '',
        iconEmoji: readString(j, 'iconEmoji'),
        createdAt: readDateTime(j, 'createdAt'),
        startSeconds: readDouble(j, 'startSeconds'),
      );
  final String minuteId;
  final String title;
  final String? iconEmoji;
  final DateTime? createdAt;
  /// S11-01b: the moment in the recording the claim came from, when known.
  final double? startSeconds;
}

class AskAllAnswer {
  const AskAllAnswer({required this.answer, required this.sources});
  factory AskAllAnswer.fromJson(Map<String, dynamic> j) =>
      AskAllAnswer(answer: readString(j, 'answer') ?? '', sources: readObjectList(j, 'sources').map(AskAllSource.fromJson).toList());
  final String answer;
  final List<AskAllSource> sources;
}

/// One semantic-search hit; `score` is 1 = identical … 0 = unrelated.
class SearchHit {
  const SearchHit({required this.minuteId, required this.title, required this.score});
  factory SearchHit.fromJson(Map<String, dynamic> j) =>
      SearchHit(minuteId: readRequiredString(j, 'minuteId'), title: readString(j, 'title') ?? '', score: readDouble(j, 'score') ?? 0);
  final String minuteId;
  final String title;
  final double score;
}

