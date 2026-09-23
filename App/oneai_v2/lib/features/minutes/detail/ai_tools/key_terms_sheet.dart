import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/tool_sheet.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';

class KeyTermsSheet extends ConsumerWidget {
  const KeyTermsSheet({required this.minuteId, super.key});
  final String minuteId;
  static Future<void> show(BuildContext context, String minuteId) => ToolSheet.present(context, KeyTermsSheet(minuteId: minuteId));

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToolSheet<KeyTerms>(
        title: context.l10n.keyTerms,
        value: ref.watch(keyTermsProvider(minuteId)),
        onRegenerate: () => ref.read(keyTermsProvider(minuteId).notifier).regenerate(),
        builder: (context, terms) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          itemCount: terms.terms.length,
          separatorBuilder: (_, __) => const Divider(height: 24),
          itemBuilder: (context, i) {
            final t = terms.terms[i];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.term, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(t.definition, style: context.textTheme.bodyMedium),
                if (t.quote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('“${t.quote}”', style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600], fontStyle: FontStyle.italic)),
                ],
              ],
            );
          },
        ),
      );
}
