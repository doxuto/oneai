import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/data/services/admob/interstitial_ad_service.dart';
import 'package:codebase_ai/domain/mappers/minute_mapper.dart';
import 'package:codebase_ai/domain/models/minute_model.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/domain/use_cases/tag_usecase.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/features/home/view_model/home_bloc.dart';
import 'package:codebase_ai/ui/features/home/view_model/minute_item_bloc.dart';
import 'package:codebase_ai/ui/features/home/widgets/tag_chip.dart';
import 'package:codebase_ai/utils/dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// Card widget for displaying a minute item in the home screen
class MinuteItemCard extends StatelessWidget {
  /// The minute item to display
  final Minute item;

  /// Creates a new [MinuteItemCard] instance
  const MinuteItemCard({required this.item, super.key});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () async {
      await HapticFeedback.lightImpact();
      if (!context.mounted) return;
      await context.read<InterstitialAdService>().showBeforeSummaryEnter(context: context);
      if (!context.mounted) return;
      await context.push(Routes.transcriptionSummary, extra: item.id);
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
            _buildAvatar(context),
            gapW16,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildTitle(context), gapH8, _buildInfo(context)],
              ),
            ),
            _buildMoreButton(context),
          ],
        ),
      ),
    ),
  );

  Widget _buildAvatar(BuildContext context) => CircleAvatar(
    radius: 24,
    backgroundColor: const Color(0xFFEDF4FF),
    child: Text(item.iconAsset ?? '😊', style: const TextStyle(fontSize: 24)),
  );

  Widget _buildTitle(BuildContext context) =>
      Text(item.title ?? 'Untitled', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600));

  Widget _buildInfo(BuildContext context) => Row(
    children: [
      Text(
        formatDateTimeToString(item.createdAt),
        style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(153)),
      ),
      _buildDot(context),
      Text(
        item.duration ?? '0:00',
        style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onSurface.withAlpha(153)),
      ),
    ],
  );

  Widget _buildDot(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Container(
      width: 4,
      height: 4,
      decoration: BoxDecoration(color: context.colorScheme.onSurface.withAlpha(153), shape: BoxShape.circle),
    ),
  );

  Widget _buildMoreButton(BuildContext context) => PopupMenuButton<String>(
    offset: const Offset(0, 40),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    onSelected: (value) {
      switch (value) {
        case 'edit_name':
          _showEditNameDialog(context);
          break;
        case 'edit_icon':
          _showEditIconDialog(context);
          break;
        case 'manage_tags':
          _showManageTagsDialog(context);
          break;
        case 'delete':
          _showDeleteConfirmationDialog(context);
          break;
      }
    },
    itemBuilder:
        (context) => [
          _buildPopupMenuItem(context, 'edit_name', context.loc.editName, Assets.editIcon),
          const PopupMenuItem<String>(
            height: 1,
            enabled: false,
            padding: EdgeInsets.zero,
            child: Divider(color: Color(0xFFBDBDBD), height: 1),
          ),
          _buildPopupMenuItem(context, 'edit_icon', context.loc.editIcon, Assets.smileIcon),
          const PopupMenuItem<String>(
            height: 1,
            enabled: false,
            padding: EdgeInsets.zero,
            child: Divider(color: Color(0xFFBDBDBD), height: 1),
          ),
          _buildPopupMenuItem(context, 'manage_tags', context.loc.manageTags, Assets.tagsIcon),
          const PopupMenuItem<String>(
            height: 1,
            enabled: false,
            padding: EdgeInsets.zero,
            child: Divider(color: Color(0xFFBDBDBD), height: 1),
          ),
          _buildPopupMenuItem(context, 'delete', context.loc.delete, Assets.deleteIcon),
        ],
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(Icons.more_horiz, color: context.colorScheme.onSurface.withAlpha(153)),
    ),
  );

  PopupMenuItem<String> _buildPopupMenuItem(BuildContext context, String value, String title, String icon) =>
      PopupMenuItem<String>(
        value: value,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: context.textTheme.bodyMedium?.copyWith(
                color: value == 'delete' ? const Color(0xFFE41919) : context.colorScheme.onSurface,
              ),
            ),
            SvgPicture.asset(icon, width: 16, height: 16),
          ],
        ),
      );

  void _showDeleteConfirmationDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text(context.loc.confirmDeletion, textAlign: TextAlign.center, style: context.textTheme.titleLarge),
            content: Text(
              context.loc.deleteNoteConfirmation,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            actionsPadding: EdgeInsets.zero,
            actions: [
              const Divider(height: 1, color: Color(0xFFBDBDBD)),
              IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(dialogContext).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.cancel,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          // Delete using the bloc
                          context.read<HomeBloc>().add(HomeEvent.deleteMinuteItem(id: item.id));
                          Navigator.of(dialogContext).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.delete,
                          style: context.textTheme.labelLarge?.copyWith(color: const Color(0xFFE41919)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  void _showEditNameDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController(text: item.title);

    showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text(context.loc.editName, textAlign: TextAlign.center, style: context.textTheme.titleLarge),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.loc.enterNewName, textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints.tightFor(width: getDialogWidth(context)),
                  child: TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    autofocus: true,
                  ),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            actionsPadding: EdgeInsets.zero,
            actions: [
              const Divider(height: 1, color: Color(0xFFBDBDBD)),
              IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(dialogContext).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.cancel,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          // Update name using the bloc
                          final newName = nameController.text.trim();
                          if (newName.isNotEmpty) {
                            context.read<HomeBloc>().add(HomeEvent.updateMinuteName(id: item.id, newName: newName));
                          }
                          Navigator.of(dialogContext).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.save,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  void _showEditIconDialog(BuildContext context) {
    final TextEditingController iconController = TextEditingController(text: '');
    String? errorText;

    showDialog<void>(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: Text(context.loc.editIcon, textAlign: TextAlign.center, style: context.textTheme.titleLarge),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.loc.enterNewIcon, textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
                const SizedBox(height: 16),
                StatefulBuilder(
                  builder:
                      (context, setState) => ConstrainedBox(
                        constraints: BoxConstraints.tightFor(width: getDialogWidth(context)),
                        child: TextField(
                          controller: iconController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            hintText: 'e.g. 😊',
                            hintStyle: context.textTheme.headlineSmall?.copyWith(
                              color: context.colorScheme.onSurface.withAlpha(153),
                            ),
                            errorText: errorText,
                          ),
                          autofocus: true,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            actionsPadding: EdgeInsets.zero,
            actions: [
              const Divider(height: 1, color: Color(0xFFBDBDBD)),
              IntrinsicHeight(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(dialogContext).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          context.loc.cancel,
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                    Expanded(
                      child: Builder(
                        builder:
                            (buttonContext) => TextButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                final input = iconController.text.trim();
                                final isSingleEmoji = RegExp(
                                  r'^(?:[\uD800-\uDBFF][\uDC00-\uDFFF]|[\u2600-\u27BF]|[\uFE0F\u200D\u2640-\u2642\u2695-\u2696\u2708-\u2709\u2712-\u2714\u2716-\u2717\u2721-\u2728\u2733-\u2734\u2744-\u2747\u2753-\u2755\u2764-\u2765\u2795-\u2797\u27A1-\u27B0\u2934-\u2935\u2B05-\u2B07\u2B1B-\u2B1C\u2B50-\u2B55\u3030\u303D\u3297\u3299]|[\uE000-\uF8FF]|[\uD83C-\uDBFF][\uDC00-\uDFFF])$',
                                ).hasMatch(input);
                                if (input.isEmpty || !isSingleEmoji) {
                                  (dialogContext as Element).markNeedsBuild();
                                  errorText = 'Please enter a single emoji.';
                                  return;
                                }
                                Navigator.of(dialogContext).pop();
                                context.read<HomeBloc>().add(HomeEvent.updateMinuteIcon(id: item.id, iconAsset: input));
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                                ),
                              ),
                              child: Text(
                                context.loc.save,
                                style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  void _showManageTagsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder:
          (dialogContext) => BlocProvider(
            create:
                (_) => MinuteItemBloc(
                  tagUseCase: context.read<TagUseCase>(),
                  minuteUseCase: context.read<MinuteUseCase>(),
                  minute: item,
                )..add(const MinuteItemEvent.loadTags()),
            child: BlocBuilder<MinuteItemBloc, MinuteItemState>(
              builder:
                  (context, state) => Dialog(
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
                              Text(
                                context.loc.manageTags,
                                style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await HapticFeedback.lightImpact();
                                  if (!dialogContext.mounted) return;
                                  context.read<MinuteItemBloc>().add(const MinuteItemEvent.saveTags());
                                  Navigator.of(dialogContext).pop();
                                },
                                child: Text(
                                  context.loc.done,
                                  style: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.primary),
                                ),
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
                                if (state.isLoading)
                                  const Center(child: CircularProgressIndicator())
                                else if (state.tags.isEmpty)
                                  Container(
                                    height: 48,
                                    alignment: Alignment.centerLeft,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F5F5),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      'No tags created yet',
                                      style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children:
                                        state.tags.map((tag) {
                                          final tagId = tag.id;
                                          final isSelected = state.selectedTagIds.contains(tagId);
                                          return TagChip(
                                            tag: tag,
                                            selected: isSelected,
                                            onTap: () async {
                                              await HapticFeedback.lightImpact();
                                              if (!dialogContext.mounted) return;
                                              context.read<MinuteItemBloc>().add(MinuteItemEvent.toggleTag(tagId));
                                            },
                                          );
                                        }).toList(),
                                  ),
                                if (state.errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(
                                      state.errorMessage!,
                                      style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.error),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
          ),
    );
  }

  Widget _buildIconOption(String iconAsset, String selectedIcon, Function(String) onSelect) {
    final bool isSelected = iconAsset == selectedIcon;

    return InkWell(
      onTap: () => onSelect(iconAsset),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey.shade300, width: isSelected ? 2 : 1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(child: SvgPicture.asset(iconAsset, width: 24, height: 24)),
      ),
    );
  }
}
