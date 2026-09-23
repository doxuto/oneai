import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/state_views.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/data/models/tag_models.dart';
import 'package:one_ai/features/minutes/home/home_controller.dart';
import 'package:one_ai/features/tags/tag_actions.dart';
import 'package:one_ai/features/tags/tag_dialogs.dart';

/// Create / rename / delete tags with note counts. v1 only had create (Home)
/// and delete (long-press); rename is new.
class TagManagerSheet extends ConsumerWidget {
  const TagManagerSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const TagManagerSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsListProvider);
    final l10n = context.l10n;
    ref.listen(tagActionsProvider, (_, next) {
      if (next.lastError != null) {
        AppSnack.failure(context, next.lastError);
        ref.read(tagActionsProvider.notifier).clearError();
      }
    });
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(children: [
                Expanded(child: Text(l10n.manageTags, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                TextButton.icon(
                  onPressed: () => showCreateTagDialog(context, ref),
                  icon: const Icon(Icons.add_circle_rounded, color: AppColors.brandBlue, size: 18),
                  label: Text(l10n.createTag, style: const TextStyle(color: AppColors.brandBlue)),
                ),
                InkWell(onTap: () => Navigator.pop(context), borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset(Assets.closeIcon, width: 24, height: 24))),
              ]),
            ),
            Expanded(
              child: switch (tags) {
                AsyncData(:final value) when value.isEmpty => EmptyState(title: l10n.noTagsYet),
                AsyncData(:final value) => ListView.separated(
                    itemCount: value.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16, color: Color(0xFFF0F0F0)),
                    itemBuilder: (context, i) => _TagRow(tag: value[i]),
                  ),
                AsyncError(:final error) => ErrorState(error: error),
                _ => const LoadingState(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends ConsumerWidget {
  const _TagRow({required this.tag});
  final Tag tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListTile(
      title: Text(tag.name),
      subtitle: Text(l10n.noteCount(tag.minuteCount), style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: SvgPicture.asset(Assets.editIcon, width: 18, height: 18), onPressed: () => _rename(context, ref)),
        IconButton(icon: SvgPicture.asset(Assets.deleteIcon, width: 18, height: 18), onPressed: () => showDeleteTagDialog(context, ref, tag)),
      ]),
    );
  }

  void _rename(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: tag.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.rename,
        confirmLabel: ctx.l10n.save,
        content: ConstrainedBox(
          constraints: BoxConstraints.tightFor(width: dialogWidth(ctx)),
          child: TextField(controller: controller, autofocus: true, decoration: dialogFieldDecoration(ctx, hintText: ctx.l10n.tagName)),
        ),
        onConfirm: () async {
          HapticFeedback.lightImpact();
          Navigator.of(ctx).pop();
          await ref.read(tagActionsProvider.notifier).rename(tag.id, controller.text);
        },
      ),
    );
  }
}
