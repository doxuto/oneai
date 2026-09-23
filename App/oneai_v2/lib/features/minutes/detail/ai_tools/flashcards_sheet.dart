import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/tool_sheet.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';
import 'package:one_ai/features/study/review_store.dart';
import 'package:one_ai/features/study/sm2.dart';

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
  /// S11-03: "Review" mode shows only the cards SM-2 says are due and asks
  /// for a grade after each flip; "Browse" is the v1 swipe-through.
  bool _review = false;

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
        builder: (context, cards) => _review ? _ReviewMode(minuteId: widget.minuteId, cards: cards, onExit: () => setState(() => _review = false)) : Column(
          children: [
            _ReviewBar(minuteId: widget.minuteId, cards: cards, onStart: () => setState(() => _review = true)),
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


/// "N due · Review" row above the browse pager.
class _ReviewBar extends ConsumerWidget {
  const _ReviewBar({required this.minuteId, required this.cards, required this.onStart});
  final String minuteId;
  final Flashcards cards;
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final schedules = ref.watch(reviewSchedulesProvider(minuteId)).valueOrNull ?? const {};
    final now = ref.read(clockProvider)();
    final due = Sm2.dueOrder([for (final c in cards.items) schedules[c.question]], now).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          Text(l10n.cardsDue(due), style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
          const Spacer(),
          TextButton(
            onPressed: due == 0 ? null : () { HapticFeedback.lightImpact(); onStart(); },
            child: Text(l10n.reviewDue, style: TextStyle(color: due == 0 ? Colors.grey : AppColors.brandBlueAlt, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ReviewMode extends ConsumerStatefulWidget {
  const _ReviewMode({required this.minuteId, required this.cards, required this.onExit});
  final String minuteId;
  final Flashcards cards;
  final VoidCallback onExit;
  @override
  ConsumerState<_ReviewMode> createState() => _ReviewModeState();
}

class _ReviewModeState extends ConsumerState<_ReviewMode> {
  late List<int> _queue;
  bool _flipped = false;
  int _done = 0;

  @override
  void initState() {
    super.initState();
    final schedules = ref.read(reviewSchedulesProvider(widget.minuteId)).valueOrNull ?? const {};
    _queue = Sm2.dueOrder([for (final c in widget.cards.items) schedules[c.question]], ref.read(clockProvider)());
  }

  Future<void> _grade(ReviewGrade g) async {
    final card = widget.cards.items[_queue.first];
    await HapticFeedback.selectionClick();
    await ref.read(reviewSchedulesProvider(widget.minuteId).notifier).grade(card.question, g);
    if (!mounted) return;
    setState(() {
      _queue.removeAt(0);
      if (g == ReviewGrade.again) _queue.add(widget.cards.items.indexOf(card)); // see it again this session
      _flipped = false;
      _done += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 48, color: AppColors.brandBlue),
            gapH16,
            Text(l10n.reviewDone(_done), textAlign: TextAlign.center, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            gapH8,
            Text(l10n.reviewComeBack, textAlign: TextAlign.center, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
            gapH24,
            TextButton(onPressed: widget.onExit, child: Text(l10n.done, style: const TextStyle(color: AppColors.brandBlueAlt))),
          ],
        ),
      );
    }
    final card = widget.cards.items[_queue.first];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            Text(l10n.cardsLeft(_queue.length), style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[700])),
            const Spacer(),
            TextButton(onPressed: widget.onExit, child: Text(l10n.back, style: const TextStyle(color: AppColors.brandBlueAlt))),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: GestureDetector(
              onTap: () { HapticFeedback.lightImpact(); setState(() => _flipped = !_flipped); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: _flipped ? AppColors.brandBlue : const Color(0xFFEDF4FF), borderRadius: BorderRadius.circular(16)),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_flipped ? l10n.answerLabel : l10n.questionLabel, style: context.textTheme.labelLarge?.copyWith(color: _flipped ? Colors.white70 : Colors.grey[600])),
                    const SizedBox(height: 16),
                    Text(_flipped ? card.answer : card.question, textAlign: TextAlign.center, style: context.textTheme.titleMedium?.copyWith(color: _flipped ? Colors.white : Colors.black, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 24),
                    if (!_flipped) Text(l10n.flipCard, style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Grades only after the flip — grading an unseen answer is noise.
        AnimatedOpacity(
          opacity: _flipped ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: IgnorePointer(
            ignoring: !_flipped,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                children: [
                  for (final (g, label, color) in [
                    (ReviewGrade.again, l10n.gradeAgain, AppColors.destructiveRed),
                    (ReviewGrade.hard, l10n.gradeHard, const Color(0xFFE59A00)),
                    (ReviewGrade.good, l10n.gradeGood, AppColors.brandBlueAlt),
                    (ReviewGrade.easy, l10n.gradeEasy, const Color(0xFF2E9E5B)),
                  ]) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _grade(g),
                        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(vertical: 12)),
                        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (g != ReviewGrade.easy) gapW8,
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
