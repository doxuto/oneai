import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/failure_text.dart' show failureText;
import 'package:one_ai/core/widgets/format.dart';
import 'package:one_ai/core/widgets/loading_dots.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/minutes/home/home_controller.dart';
import 'package:one_ai/features/tags/tag_chip.dart';
import 'package:one_ai/features/tags/tag_dialogs.dart';

/// Port of v1 MinuteItemCard. Same card, same menu; the live status from
/// Firestore now shows in the info row (v1 had no status to show).
class MinuteItemCard extends ConsumerWidget {
  const MinuteItemCard({required this.item, super.key});
  final MinuteSummary item;

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
        onTap: () async {
          await HapticFeedback.lightImpact();
          if (!context.mounted) return;
          await ref.read(interstitialHookProvider).maybeShow(AdPlacement.preSummary);
          if (!context.mounted) return;
          await context.push(Routes.transcriptionSummary, extra: SummaryArgs(minuteId: item.id));
        },
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: context.colorScheme.surfaceContainerHighest),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFEDF4FF),
                  child: Text(item.iconEmoji ?? '😊', style: const TextStyle(fontSize: 24)),
                ),
                gapW16,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (item.pinned) ...[
                          Icon(Icons.push_pin, size: 14, color: context.colorScheme.onSurface.withAlpha(153)),
                          gapW4,
                        ],
                        Expanded(child: Text(item.title, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
                      ]),
                      gapH8,
                      _Info(item: item),
                    ],
                  ),
                ),
                _MoreButton(item: item),
              ],
            ),
          ),
        ),
      );
}

class _Info extends StatelessWidget {
  const _Info({required this.item});
  final MinuteSummary item;

  @override
  Widget build(BuildContext context) {
    final muted = context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(153));
    final l10n = context.l10n;
    Widget tail;
    if (item.status.isProcessing || item.status == MinuteStatus.uploading) {
      tail = Row(mainAxisSize: MainAxisSize.min, children: [
        Text(switch (item.status) {
          MinuteStatus.uploading => l10n.statusUploading,
          MinuteStatus.queued => l10n.statusQueued,
          MinuteStatus.transcribing => l10n.statusTranscribing,
          _ => l10n.statusSummarizing,
        }, style: muted),
        gapW8,
        const LoadingDots(size: 5, spacing: 4, color: AppColors.brandBlue),
      ]);
    } else if (item.status == MinuteStatus.failed) {
      tail = Text(l10n.statusFailed, style: muted?.copyWith(color: AppColors.destructiveRed));
    } else if (item.status == MinuteStatus.cancelled) {
      tail = Text(l10n.statusCancelled, style: muted);
    } else {
      tail = Text(item.sourceType == SourceType.pdf ? 'PDF' : formatDurationLong(item.durationSeconds), style: muted);
    }
    return Row(
      children: [
        Text(formatDateTime(item.createdAt), style: muted),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(width: 4, height: 4, decoration: BoxDecoration(color: context.colorScheme.onSurface.withAlpha(153), shape: BoxShape.circle)),
        ),
        Flexible(child: tail),
      ],
    );
  }
}

class _MoreButton extends ConsumerWidget {
  const _MoreButton({required this.item});
  final MinuteSummary item;

  static const _divider = PopupMenuItem<String>(height: 1, enabled: false, padding: EdgeInsets.zero, child: Divider(color: AppColors.dividerGrey, height: 1));

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) {
          switch (value) {
            case 'pin':
              ref.read(minuteActionsProvider.notifier).setPinned(item.id, !item.pinned);
            case 'edit_name':
              _editName(context, ref);
            case 'edit_icon':
              _editIcon(context, ref);
            case 'manage_tags':
              _manageTags(context, ref);
            case 'delete':
              _delete(context, ref);
          }
        },
        itemBuilder: (context) => [
          _item(context, 'pin', item.pinned ? context.l10n.unpinNote : context.l10n.pinNote, null),
          _divider,
          _item(context, 'edit_name', context.l10n.editName, Assets.editIcon),
          _divider,
          _item(context, 'edit_icon', context.l10n.editIcon, Assets.smileIcon),
          _divider,
          _item(context, 'manage_tags', context.l10n.manageTags, Assets.tagsIcon),
          _divider,
          _item(context, 'delete', context.l10n.delete, Assets.deleteIcon),
        ],
        child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.more_horiz, color: context.colorScheme.onSurface.withAlpha(153))),
      );

  PopupMenuItem<String> _item(BuildContext context, String value, String title, String? icon) => PopupMenuItem<String>(
        value: value,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: context.textTheme.bodyMedium?.copyWith(color: value == 'delete' ? AppColors.destructiveRed : context.colorScheme.onSurface)),
            if (icon != null) SvgPicture.asset(icon, width: 16, height: 16) else Icon(item.pinned ? Icons.push_pin_outlined : Icons.push_pin, size: 16, color: context.colorScheme.onSurface),
          ],
        ),
      );

  void _delete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.confirmDeletion,
        confirmLabel: ctx.l10n.delete,
        destructive: true,
        content: Text(ctx.l10n.deleteNoteConfirmation, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
        onConfirm: () async {
          Navigator.of(ctx).pop();
          final ok = await ref.read(minuteActionsProvider.notifier).delete(item.id);
          if (!ok && context.mounted) AppSnack.failure(context, ref.read(minuteActionsProvider).lastError);
        },
      ),
    );
  }

  void _editName(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: item.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.editName,
        confirmLabel: ctx.l10n.save,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ctx.l10n.enterNewName, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints.tightFor(width: dialogWidth(ctx)),
              child: TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              ),
            ),
          ],
        ),
        onConfirm: () async {
          Navigator.of(ctx).pop();
          final name = controller.text.trim();
          if (name.isEmpty) return;
          final ok = await ref.read(minuteActionsProvider.notifier).rename(item.id, name);
          if (!ok && context.mounted) AppSnack.failure(context, ref.read(minuteActionsProvider).lastError);
        },
      ),
    );
  }

  void _editIcon(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    String? errorText;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => StyledDialog(
          title: ctx.l10n.editIcon,
          confirmLabel: ctx.l10n.save,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ctx.l10n.enterNewIcon, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints.tightFor(width: dialogWidth(ctx)),
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(fontSize: 24),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    hintText: ctx.l10n.emojiHint,
                    hintStyle: ctx.textTheme.headlineSmall?.copyWith(color: ctx.colorScheme.onSurface.withAlpha(153)),
                    errorText: errorText,
                  ),
                ),
              ),
            ],
          ),
          onConfirm: () async {
            final input = controller.text.trim();
            if (input.isEmpty || !singleEmoji.hasMatch(input)) {
              setState(() => errorText = ctx.l10n.singleEmojiOnly);
              return;
            }
            Navigator.of(ctx).pop();
            final ok = await ref.read(minuteActionsProvider.notifier).setIcon(item.id, input);
            if (!ok && context.mounted) AppSnack.failure(context, ref.read(minuteActionsProvider).lastError);
          },
        ),
      ),
    );
  }

  void _manageTags(BuildContext context, WidgetRef ref) {
    showDialog<void>(context: context, builder: (_) => _ManageTagsDialog(item: item));
  }
}

/// v1's "Manage tags" dialog: chips toggle locally, Done saves once.
class _ManageTagsDialog extends ConsumerStatefulWidget {
  const _ManageTagsDialog({required this.item});
  final MinuteSummary item;
  @override
  ConsumerState<_ManageTagsDialog> createState() => _ManageTagsDialogState();
}

class _ManageTagsDialogState extends ConsumerState<_ManageTagsDialog> {
  late final Set<String> _selected = widget.item.tagIds.toSet();
  Object? _error;

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsListProvider);
    final l10n = context.l10n;
    return Dialog(
      backgroundColor: context.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 8, bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.manageTags, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                TextButton(
                  onPressed: () async {
                    await HapticFeedback.lightImpact();
                    final ok = await ref.read(minuteActionsProvider.notifier).setTags(widget.item.id, _selected.toList());
                    if (!mounted) return;
                    if (ok) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _error = ref.read(minuteActionsProvider).lastError);
                    }
                  },
                  child: Text(l10n.done, style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.primary)),
                ),
              ],
            ),
            gapH16,
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  switch (tags) {
                    AsyncData(:final value) when value.isEmpty => Container(
                        height: 48,
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(l10n.noTagsYet, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                      ),
                    AsyncData(:final value) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in value)
                            TagChip(
                              label: tag.name,
                              selected: _selected.contains(tag.id),
                              onTap: () => setState(() => _selected.contains(tag.id) ? _selected.remove(tag.id) : _selected.add(tag.id)),
                            ),
                          TagChip(
                            label: '+ ${l10n.createTag}',
                            onTap: () async {
                              final created = await showCreateTagDialog(context, ref);
                              if (created != null) setState(() => _selected.add(created.id));
                            },
                          ),
                        ],
                      ),
                    AsyncError(:final error) => Text(failureText(context, error), style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.error)),
                    _ => const Center(child: CircularProgressIndicator()),
                  },
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(failureText(context, _error), style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.error)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
