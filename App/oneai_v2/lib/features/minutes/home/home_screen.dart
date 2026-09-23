import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/state_views.dart';
import 'package:one_ai/data/models/tag_models.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/billing/paywall.dart';
import 'package:one_ai/features/credits/premium_button.dart';
import 'package:one_ai/features/minutes/detail/feedback_dialog.dart';
import 'package:one_ai/features/minutes/home/home_controller.dart';
import 'package:one_ai/features/minutes/home/intro_basic_popup.dart';
import 'package:one_ai/features/minutes/home/minute_item_card.dart';
import 'package:one_ai/features/minutes/home/new_minutes_bottom_sheet.dart';
import 'package:one_ai/features/tags/tag_chip.dart';
import 'package:one_ai/features/tags/tag_dialogs.dart';

/// Port of v1 HomeScreen. Same header, title, chip row, list, FAB. The list
/// is live (Firestore) so pull-to-refresh only re-reads getMe; pagination
/// is gone because the stream carries the newest 100 notes.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => maybeShowIntroBasicPopup(context, ref));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(minuteActionsProvider, (_, next) {
      if (next.lastError != null) {
        AppSnack.failure(context, next.lastError);
        ref.read(minuteActionsProvider.notifier).clearError();
      }
    });
    final minutes = ref.watch(visibleMinutesProvider);
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Header(),
              gapH16,
              Text(context.l10n.myNotes, style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              gapH24,
              const _TagRow(),
              gapH24,
              Expanded(
                child: switch (minutes) {
                  AsyncData(:final value) when value.isEmpty => const _EmptyNotes(),
                  AsyncData(:final value) => ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 80), // clear the FAB
                      itemCount: value.length,
                      itemBuilder: (_, i) => Padding(padding: const EdgeInsets.only(bottom: 16), child: MinuteItemCard(item: value[i])),
                    ),
                  AsyncError(:final error) => ErrorState(error: error, onRetry: () => ref.invalidate(minutesListProvider)),
                  _ => const LoadingState(),
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Builder(
        builder: (context) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            curve: Curves.ease,
            offset: bottomInset > 0 ? const Offset(0, 1.2) : Offset.zero,
            child: AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: bottomInset > 0 ? 0.0 : 1.0, child: const _NewNoteButton()),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          PremiumButton(
            state: premium ? PremiumButtonState.premium : PremiumButtonState.upgrade,
            onPressed: premium
                ? null
                : () async {
                    await HapticFeedback.lightImpact();
                    await ref.read(paywallProvider).present();
                  },
          ),
          const Spacer(),
          _ActionButton(icon: Assets.messageIcon, onTap: () async {
            await HapticFeedback.lightImpact();
            if (context.mounted) await showFeedbackDialog(context);
          }),
          gapW16,
          _ActionButton(icon: Assets.settingsIcon, onTap: () { HapticFeedback.lightImpact(); context.push(Routes.settings); }),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap});
  final String icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(8), child: SvgPicture.asset(icon, width: 24, height: 24)),
      );
}

/// Create-tag pill, "All" (only when there are >2 tags, as v1), then one chip
/// per tag. Long-press deletes.
class _TagRow extends ConsumerWidget {
  const _TagRow();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsListProvider).valueOrNull ?? const <Tag>[];
    final selected = ref.watch(selectedTagIdsProvider);
    final allSlot = tags.length > 2 ? 1 : 0;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tags.length + 1 + allSlot,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == 0) return const _CreateTagButton();
          if (index <= allSlot) {
            return TagChip(label: context.l10n.allTag, selected: selected.isEmpty, onTap: () => ref.read(selectedTagIdsProvider.notifier).clear());
          }
          final tag = tags[index - 1 - allSlot];
          return TagChip(
            label: tag.name,
            selected: selected.contains(tag.id),
            onTap: () => ref.read(selectedTagIdsProvider.notifier).toggle(tag.id),
            onLongPress: () => showDeleteTagDialog(context, ref, tag),
          );
        },
      ),
    );
  }
}

class _CreateTagButton extends ConsumerWidget {
  const _CreateTagButton();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
        height: 40,
        decoration: BoxDecoration(color: TagChip.idleColor, borderRadius: BorderRadius.circular(20)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () { HapticFeedback.lightImpact(); showCreateTagDialog(context, ref); },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_circle_rounded, color: AppColors.brandBlue, size: 18),
                  gapW8,
                  Text(context.l10n.createTag, style: context.textTheme.labelLarge?.copyWith(color: AppColors.brandBlue, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ),
        ),
      );
}

class _EmptyNotes extends StatelessWidget {
  const _EmptyNotes();
  @override
  Widget build(BuildContext context) => CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Align(
              alignment: const Alignment(0, -0.4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(color: Color(0xFFE1EDFF), shape: BoxShape.circle),
                    child: Center(child: SvgPicture.asset(Assets.clockIcon, width: 32, height: 32, colorFilter: const ColorFilter.mode(AppColors.brandBlue, BlendMode.srcIn))),
                  ),
                  gapH16,
                  Text(context.l10n.noNotesYet, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                  gapH8,
                  Text(context.l10n.tapButtonBelowToStart, style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
        ],
      );
}

class _NewNoteButton extends StatelessWidget {
  const _NewNoteButton();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: () { HapticFeedback.lightImpact(); NewMinutesBottomSheet.show(context); },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add, color: Colors.white),
                gapW8,
                Text(context.l10n.newNote, style: context.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}
