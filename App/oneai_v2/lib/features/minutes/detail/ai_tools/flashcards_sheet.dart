import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/tool_sheet.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';

class FlashcardsSheet extends ConsumerStatefulWidget {
  const FlashcardsSheet({required this.minuteId, super.key});
  final String minuteId;
  static Future<void> show(BuildContext context, String minuteId) => ToolSheet.present(context, FlashcardsSheet(minuteId: minuteId));
  @override
  ConsumerState<FlashcardsSheet> createState() => _FlashcardsSheetState();
}

class _FlashcardsSheetState extends ConsumerState<FlashcardsSheet> {
  final PageController _page = PageController();
  final Set<int> _flipped = {};

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ToolSheet<Flashcards>(
        title: context.l10n.flashcards,
        value: ref.watch(flashcardsProvider(widget.minuteId)),
        onRegenerate: () { setState(_flipped.clear); ref.read(flashcardsProvider(widget.minuteId).notifier).regenerate(); },
        builder: (context, cards) => Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _page,
                itemCount: cards.items.length,
                itemBuilder: (context, i) {
                  final card = cards.items[i];
                  final flipped = _flipped.contains(i);
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: GestureDetector(
                      onTap: () { HapticFeedback.lightImpact(); setState(() => flipped ? _flipped.remove(i) : _flipped.add(i)); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: flipped ? AppColors.brandBlue : const Color(0xFFEDF4FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(flipped ? context.l10n.answerLabel : '${i + 1} / ${cards.items.length}', style: context.textTheme.labelLarge?.copyWith(color: flipped ? Colors.white70 : Colors.grey[600])),
                            const SizedBox(height: 16),
                            Text(flipped ? card.answer : card.question, textAlign: TextAlign.center, style: context.textTheme.titleMedium?.copyWith(color: flipped ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 24),
                            Text(context.l10n.flipCard, style: context.textTheme.bodySmall?.copyWith(color: flipped ? Colors.white70 : Colors.grey[600])),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
}
