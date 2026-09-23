import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/features/minutes/ask/ask_all_controller.dart';
import 'package:one_ai/features/tags/tag_chip.dart';

/// S11-01 — "Ask your notes": one chat over every note. Same bubbles as the
/// per-note Chat tab; each answer lists the notes it cited as tappable chips.
class AskAllScreen extends ConsumerStatefulWidget {
  const AskAllScreen({super.key});
  @override
  ConsumerState<AskAllScreen> createState() => _AskAllScreenState();
}

class _AskAllScreenState extends ConsumerState<AskAllScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    HapticFeedback.lightImpact();
    _input.clear();
    if (text != null) _focus.unfocus();
    ref.read(askAllControllerProvider.notifier).send(t);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(askAllControllerProvider);
    ref.listen(askAllControllerProvider, (prev, next) {
      if (next.messages.length != (prev?.messages.length ?? 0) || next.sending) _scrollToEnd();
      if (next.sendError != null && next.sendError != prev?.sendError) AppSnack.failure(context, next.sendError);
    });
    final showTyping = state.sending && state.messages.isNotEmpty && state.messages.last.role == ChatRole.assistant && state.messages.last.text.isEmpty;
    final examples = [l10n.askAllExample1, l10n.askAllExample2, l10n.askAllExample3];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(l10n.askYourNotes, style: context.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        actions: [
          if (state.messages.isNotEmpty)
            IconButton(tooltip: l10n.newConversation, icon: const Icon(Icons.refresh), onPressed: () => ref.read(askAllControllerProvider.notifier).clear()),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (state.messages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l10n.askAllWelcome, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                    ),
                  for (final m in state.messages)
                    if (!(m.role == ChatRole.assistant && m.text.isEmpty))
                      _Bubble(entry: m, onSource: (s) => context.push(Routes.transcriptionSummary, extra: SummaryArgs(minuteId: s.minuteId))),
                  if (showTyping) Padding(padding: const EdgeInsets.all(16), child: Text('…', style: context.textTheme.titleLarge?.copyWith(color: context.colorScheme.primary))),
                  if (state.failedQuestion != null && !state.sending)
                    Center(child: TextButton(onPressed: () => ref.read(askAllControllerProvider.notifier).retryLast(), child: Text(l10n.retry))),
                ],
              ),
            ),
          ),
          gapH8,
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state.messages.isEmpty)
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: examples.length,
                      separatorBuilder: (_, __) => gapW8,
                      itemBuilder: (context, i) => TagChip(label: examples[i], onTap: () => _send(examples[i])),
                    ),
                  ),
                gapH4,
                Container(
                  height: 43,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(45)),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16),
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            enabled: !state.sending,
                            decoration: InputDecoration(
                              hintText: l10n.askAllHint,
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
                        onTap: state.sending ? null : _send,
                        borderRadius: const BorderRadius.only(topRight: Radius.circular(24), bottomRight: Radius.circular(24)),
                        child: Center(child: SvgPicture.asset(Assets.enterIcon, width: 33, height: 33)),
                      ),
                      gapW4,
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry, required this.onSource});
  final AskAllEntry entry;
  final ValueChanged<AskAllSource> onSource;

  @override
  Widget build(BuildContext context) {
    final isBot = entry.role == ChatRole.assistant;
    final style = TextStyle(color: entry.failed ? Colors.grey : context.colorScheme.onSurface, fontSize: 16);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: isBot ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isBot) ...[
                Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: context.colorScheme.primary, shape: BoxShape.circle)),
                gapW8,
              ],
              Flexible(
                child: isBot
                    ? SelectableText(stripCitations(entry.text), style: style)
                    : Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: const Color(0xFFF2F2F2), borderRadius: BorderRadius.circular(18)),
                        child: Text(entry.text, style: style),
                      ),
              ),
              if (isBot) gapW8,
            ],
          ),
          if (entry.sources.isNotEmpty) ...[
            gapH8,
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in entry.sources)
                    TagChip(label: '${s.iconEmoji ?? '📝'} ${s.title.isEmpty ? context.l10n.untitled : s.title}', onTap: () => onSource(s)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
