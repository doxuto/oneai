import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/minutes/chat/chat_controller.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';
import 'package:one_ai/features/tags/tag_chip.dart';

/// v1 Chat tab on ChatController: messages, typing dots while the first
/// delta is pending, suggested questions as chips, the pill input.
class ChatTab extends ConsumerStatefulWidget {
  const ChatTab({required this.minuteId, required this.scrollController, super.key});
  final String minuteId;
  final ScrollController scrollController;
  @override
  ConsumerState<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<ChatTab> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.scrollController.hasClients) {
          widget.scrollController.animateTo(widget.scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider(widget.minuteId));
    final suggestions = ref.watch(shortQuestionsProvider(widget.minuteId)).valueOrNull?.data.questions ?? const <String>[];
    ref.listen(chatControllerProvider(widget.minuteId), (prev, next) {
      if (next.messages.length != (prev?.messages.length ?? 0) || next.sending) _scrollToEnd();
      if (next.sendError != null && next.sendError != prev?.sendError) AppSnack.failure(context, next.sendError);
    });
    final showTyping = chat.sending && chat.messages.isNotEmpty && chat.messages.last.role == ChatRole.assistant && chat.messages.last.text.isEmpty;
    final l10n = context.l10n;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(padding: EdgeInsets.only(bottom: 16), child: AdBannerSlot(placement: 'chat')),
                if (chat.hasOlder)
                  Center(child: TextButton(onPressed: () => ref.read(chatControllerProvider(widget.minuteId).notifier).loadOlder(), child: Text(l10n.loadOlder))),
                if (chat.messages.isEmpty && !chat.loadingHistory)
                  Padding(padding: const EdgeInsets.all(16), child: Text(l10n.chatWelcome, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]))),
                for (final m in chat.messages)
                  if (!(m.role == ChatRole.assistant && m.text.isEmpty)) _Bubble(entry: m),
                if (showTyping) const _TypingIndicator(),
                if (chat.failedQuestion != null && !chat.sending)
                  Center(child: TextButton(onPressed: () => ref.read(chatControllerProvider(widget.minuteId).notifier).retryLast(), child: Text(l10n.retry))),
              ],
            ),
          ),
        ),
        gapH16,
        SafeArea(
          minimum: const EdgeInsets.only(bottom: 16),
          child: _ChatInput(
            focusNode: _focus,
            enabled: !chat.sending,
            suggestions: suggestions,
            onSend: (text) => ref.read(chatControllerProvider(widget.minuteId).notifier).send(text),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry});
  final ChatEntry entry;

  @override
  Widget build(BuildContext context) {
    final isBot = entry.role == ChatRole.assistant;
    final style = TextStyle(color: entry.failed ? Colors.grey : context.colorScheme.onSurface, fontSize: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isBot) ...[const _BotDot(), gapW8],
          Flexible(
            child: isBot
                ? Text(entry.text, style: style)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(18)),
                    child: Text(entry.text, style: style),
                  ),
          ),
          if (isBot) gapW8,
        ],
      ),
    );
  }
}

class _BotDot extends StatelessWidget {
  const _BotDot();
  @override
  Widget build(BuildContext context) => Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: context.colorScheme.primary, shape: BoxShape.circle));
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          const _BotDot(),
          gapW8,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(18)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final delay in [0, 200, 400])
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.3, end: 1).animate(CurvedAnimation(parent: _c, curve: Interval(delay / 1200, (delay + 600) / 1200))),
                    child: Container(width: 8, height: 8, margin: const EdgeInsets.symmetric(horizontal: 2), decoration: const BoxDecoration(color: Color(0xFFBDBDBD), shape: BoxShape.circle)),
                  ),
              ],
            ),
          ),
        ]),
      );
}

class _ChatInput extends StatefulWidget {
  const _ChatInput({required this.focusNode, required this.enabled, required this.suggestions, required this.onSend});
  final FocusNode focusNode;
  final bool enabled;
  final List<String> suggestions;
  final ValueChanged<String> onSend;
  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _controller.text).trim();
    if (t.isEmpty || !widget.enabled) return;
    HapticFeedback.lightImpact();
    widget.onSend(t);
    _controller.clear();
    if (text != null) widget.focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.suggestions.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: widget.suggestions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) => TagChip(label: widget.suggestions[i], onTap: () => _send(widget.suggestions[i])),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            height: 43,
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(45)),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: TextField(
                      controller: _controller,
                      focusNode: widget.focusNode,
                      enabled: widget.enabled,
                      decoration: InputDecoration(
                        hintText: context.l10n.messageHint,
                        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                gapW16,
                InkWell(
                  onTap: _send,
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                  child: Center(child: SvgPicture.asset(Assets.enterIcon, width: 33, height: 33)),
                ),
                gapW4,
              ],
            ),
          ),
        ],
      );
}
