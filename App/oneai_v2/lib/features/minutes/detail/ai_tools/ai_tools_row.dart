import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/flashcards_sheet.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/key_terms_sheet.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/mindmap_sheet.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/quiz_sheet.dart';

/// Entry points to the study tools. v1 had the APIs but no UI for them.
class AiToolsRow extends StatelessWidget {
  const AiToolsRow({required this.detail, super.key});
  final MinuteDetail detail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tools = <(String, IconData, bool, Future<void> Function())>[
      (l10n.quiz, Icons.quiz_outlined, detail.hasArtifact(ArtifactKind.quiz), () => QuizSheet.show(context, detail.id)),
      (l10n.flashcards, Icons.style_outlined, detail.hasArtifact(ArtifactKind.flashcards), () => FlashcardsSheet.show(context, detail.id)),
      (l10n.mindmap, Icons.account_tree_outlined, detail.hasArtifact(ArtifactKind.mindmap), () => MindmapSheet.show(context, detail.id)),
      (l10n.keyTerms, Icons.menu_book_outlined, detail.hasArtifact(ArtifactKind.keyTerms), () => KeyTermsSheet.show(context, detail.id)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.studyTools, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, icon, ready, open) in tools)
              Material(
                color: const Color(0xFFEDF4FF),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () { HapticFeedback.lightImpact(); open(); },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: AppColors.brandBlue),
                        const SizedBox(width: 6),
                        Text(label, style: const TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.w500)),
                        if (ready) ...[const SizedBox(width: 6), const Icon(Icons.check_circle, size: 14, color: AppColors.brandBlue)],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
