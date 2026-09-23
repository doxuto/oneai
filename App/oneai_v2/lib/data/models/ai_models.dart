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
