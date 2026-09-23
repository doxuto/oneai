import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/tool_sheet.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';

/// Mind map as a collapsible tree (an indented outline reads better on a
/// phone than a radial graph).
class MindmapSheet extends ConsumerWidget {
  const MindmapSheet({required this.minuteId, super.key});
  final String minuteId;
  static Future<void> show(BuildContext context, String minuteId) => ToolSheet.present(context, MindmapSheet(minuteId: minuteId));

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToolSheet<Mindmap>(
        title: context.l10n.mindmap,
        value: ref.watch(mindmapProvider(minuteId)),
        onRegenerate: () => ref.read(mindmapProvider(minuteId).notifier).regenerate(),
        builder: (context, map) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            Row(children: [
              if (map.root.icon != null) Text(map.root.icon!, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 8),
              Expanded(child: Text(map.root.title, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 12),
            for (final n in map.root.children) _Node(node: n, depth: 0),
          ],
        ),
      );
}

class _Node extends StatelessWidget {
  const _Node({required this.node, required this.depth});
  final MindmapNode node;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final title = Text(node.title, style: context.textTheme.bodyMedium?.copyWith(fontWeight: depth == 0 ? FontWeight.w600 : FontWeight.w400));
    if (node.children.isEmpty) {
      return Padding(padding: EdgeInsets.only(left: 16.0 * depth + 8, top: 4, bottom: 4), child: Row(children: [const Icon(Icons.circle, size: 6, color: AppColors.brandBlue), const SizedBox(width: 8), Expanded(child: title)]));
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: depth == 0,
        tilePadding: EdgeInsets.only(left: 16.0 * depth),
        childrenPadding: EdgeInsets.zero,
        title: title,
        iconColor: AppColors.brandBlue,
        collapsedIconColor: AppColors.brandBlue,
        children: [for (final c in node.children) _Node(node: c, depth: depth + 1)],
      ),
    );
  }
}
