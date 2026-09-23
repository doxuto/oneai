import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/data/models/tag_models.dart';
import 'package:one_ai/features/tags/tag_actions.dart';

/// v1's "Create new tag" dialog. Resolves with the created tag, or null.
Future<Tag?> showCreateTagDialog(BuildContext context, WidgetRef ref) {
  final controller = TextEditingController();
  return showDialog<Tag?>(
    context: context,
    builder: (ctx) => StyledDialog(
      title: ctx.l10n.createNewTag,
      confirmLabel: ctx.l10n.create,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ctx.l10n.enterTagName, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints.tightFor(width: dialogWidth(ctx)),
            child: TextField(controller: controller, autofocus: true, decoration: dialogFieldDecoration(ctx, hintText: ctx.l10n.tagName)),
          ),
        ],
      ),
      onConfirm: () async {
        if (controller.text.trim().isEmpty) return;
        final nav = Navigator.of(ctx);
        final tag = await ref.read(tagActionsProvider.notifier).create(controller.text);
        if (tag == null && ctx.mounted) AppSnack.failure(ctx, ref.read(tagActionsProvider).lastError);
        nav.pop(tag);
      },
    ),
  );
}

/// v1's "Delete Tag" dialog (long-press on a chip).
Future<void> showDeleteTagDialog(BuildContext context, WidgetRef ref, Tag tag) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.deleteTag,
        confirmLabel: ctx.l10n.delete,
        destructive: true,
        content: Text(ctx.l10n.deleteTagConfirm(tag.name), textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
        onConfirm: () async {
          final nav = Navigator.of(ctx);
          nav.pop();
          final n = await ref.read(tagActionsProvider.notifier).delete(tag.id);
          if (n == null && context.mounted) AppSnack.failure(context, ref.read(tagActionsProvider).lastError);
        },
      ),
    );
