import 'package:codebase_ai/domain/models/chat_message_model.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:flutter/material.dart';

/// Widget to display a single chat message
class ChatMessageWidget extends StatelessWidget {
  /// The chat message to display
  final ChatMessage message;

  /// Constructor
  const ChatMessageWidget({required this.message, super.key});

  @override
  Widget build(BuildContext context) {
    final isBot = message.senderType == MessageSenderType.bot;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot) ...[_buildBotIndicator(context), gapW8],
          Flexible(
            child:
                isBot
                    ? Text(message.message, style: TextStyle(color: context.colorScheme.onSurface, fontSize: 16))
                    : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F2F2),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        message.message,
                        style: TextStyle(color: context.colorScheme.onSurface, fontSize: 16),
                      ),
                    ),
          ),
          if (isBot) ...[gapW8],
        ],
      ),
    );
  }

  Widget _buildBotIndicator(BuildContext context) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(color: context.colorScheme.primary, shape: BoxShape.circle),
  );
}

class ChatTypingIndicator extends StatelessWidget {
  const ChatTypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _buildBotIndicator(context),
          gapW8,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(18)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [_AnimatedDot(delay: 0), _AnimatedDot(delay: 200), _AnimatedDot(delay: 400)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotIndicator(BuildContext context) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.only(top: 4),
    decoration: BoxDecoration(color: context.colorScheme.primary, shape: BoxShape.circle),
  );
}

class _AnimatedDot extends StatefulWidget {
  final int delay;
  const _AnimatedDot({required this.delay});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Interval(widget.delay / 1200, (widget.delay + 600) / 1200)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: const BoxDecoration(color: Color(0xFFBDBDBD), shape: BoxShape.circle),
      ),
    );
  }
}
