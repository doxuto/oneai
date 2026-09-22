import 'package:codebase_ai/domain/models/chat_message_model.dart';

/// Sample data provider for meeting minutes
class MeetingMinuteProvider {
  /// Get a sample chat conversation for demonstration
  static ChatConversation getSampleChatConversation() => ChatConversation(
    messages: [
      ChatMessage(
        message: "Hi! I'm here to assist you with your note: Greeting Notes. How can I help?",
        senderType: MessageSenderType.bot,
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      ChatMessage(
        message: 'Hi',
        senderType: MessageSenderType.user,
        timestamp: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    ],
  );
}
