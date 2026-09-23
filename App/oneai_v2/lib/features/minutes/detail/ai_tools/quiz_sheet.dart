import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/tool_sheet.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';

class QuizSheet extends ConsumerStatefulWidget {
  const QuizSheet({required this.minuteId, super.key});
  final String minuteId;
  static Future<void> show(BuildContext context, String minuteId) => ToolSheet.present(context, QuizSheet(minuteId: minuteId));
  @override
  ConsumerState<QuizSheet> createState() => _QuizSheetState();
}

class _QuizSheetState extends ConsumerState<QuizSheet> {
  /// question index → chosen option
  final Map<int, int> _answers = {};

  @override
  Widget build(BuildContext context) => ToolSheet<Quiz>(
        title: context.l10n.quiz,
        value: ref.watch(quizProvider(widget.minuteId)),
        onRegenerate: () { setState(_answers.clear); ref.read(quizProvider(widget.minuteId).notifier).regenerate(); },
        builder: (context, quiz) {
          final l10n = context.l10n;
          final answered = _answers.length;
          final correct = _answers.entries.where((e) => quiz.items[e.key].answerIndex == e.value).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              if (answered == quiz.items.length && quiz.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(l10n.quizScore(correct, quiz.items.length), style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: AppColors.brandBlue)),
                ),
              for (final (i, item) in quiz.items.indexed) ...[
                Text('${i + 1}. ${item.question}', style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                for (final (j, opt) in item.options.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: _optionColor(i, j, item),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _answers.containsKey(i) ? null : () { HapticFeedback.lightImpact(); setState(() => _answers[i] = j); },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(children: [
                            Expanded(child: Text(opt, style: context.textTheme.bodyMedium)),
                            if (_answers[i] == j) Text(j == item.answerIndex ? l10n.quizCorrect : l10n.quizIncorrect(item.options[item.answerIndex]), style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      );

  Color _optionColor(int q, int opt, QuizItem item) {
    final chosen = _answers[q];
    if (chosen == null) return const Color(0xFFF5F5F5);
    if (opt == item.answerIndex) return const Color(0xFFCCF5E9);
    if (opt == chosen) return const Color(0xFFFFDAD4);
    return const Color(0xFFF5F5F5);
  }
}
