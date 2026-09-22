import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/domain/models/tag_model.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/features/home/widgets/tag_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Widget for the chat input field at the bottom of the chat tab
class ChatInputWidget extends StatefulWidget {
  /// Callback for when a message is sent
  final Function(String) onMessageSent;

  /// Focus node for the text field
  final FocusNode? focusNode;

  /// Suggested questions for the user
  final List<String> suggestedQuestions;

  /// Constructor
  const ChatInputWidget({required this.onMessageSent, required this.suggestedQuestions, this.focusNode, super.key});

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleSend() {
    if (_controller.text.trim().isNotEmpty) {
      HapticFeedback.lightImpact();
      widget.onMessageSent(_controller.text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Suggested Questions
      SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: widget.suggestedQuestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final question = widget.suggestedQuestions[index];
            return TagChip(
              tag: Tag(id: '', name: question),
              onTap: () {
                widget.onMessageSent(question);
                _controller.clear();
                _focusNode.unfocus();
                HapticFeedback.lightImpact();
              },
            );
          },
        ),
      ),
      const SizedBox(height: 4),
      // Chat input field
      Container(
        height: 43,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(45),
        ),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  decoration: const InputDecoration(
                    hintText: 'Message...',
                    hintStyle: TextStyle(color: Color(0xFF8E8E93)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
            ),
            gapW16,
            InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _handleSend();
              },
              borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
              child: Center(
                child: SvgPicture.asset(
                  Assets.enterIcon,
                  width: 33,
                  height: 33,
                  // colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
            gapW4,
          ],
        ),
      ),
    ],
  );
}
