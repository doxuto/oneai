import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message_model.freezed.dart';
part 'chat_message_model.g.dart';

/// Enum to represent the type of sender in the chat
enum MessageSenderType { bot, user }

/// Model representing a single chat message
@freezed
sealed class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String message,
    required MessageSenderType senderType,
    required DateTime timestamp,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => _$ChatMessageFromJson(json);
}

/// Model representing a chat conversation with all messages
@freezed
sealed class ChatConversation with _$ChatConversation {
  const factory ChatConversation({required List<ChatMessage> messages}) = _ChatConversation;

  factory ChatConversation.fromJson(Map<String, dynamic> json) => _$ChatConversationFromJson(json);
}
