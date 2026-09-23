import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/loading_dots.dart';
import 'package:one_ai/core/widgets/state_views.dart';
import 'package:one_ai/data/models/tag_models.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/billing/paywall.dart';
import 'package:one_ai/features/credits/credits_provider.dart';
import 'package:one_ai/features/credits/premium_button.dart';
import 'package:one_ai/features/minutes/detail/feedback_dialog.dart';
import 'package:one_ai/features/minutes/home/home_controller.dart';
import 'package:one_ai/features/minutes/home/intro_basic_popup.dart';
import 'package:one_ai/features/minutes/home/minute_item_card.dart';
import 'package:one_ai/features/minutes/home/new_minutes_bottom_sheet.dart';
import 'package:one_ai/features/credits/credit_gate_ui.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/transcription/incoming_share.dart';
import 'package:one_ai/features/transcription/new_minute_request_builder.dart';
import 'package:one_ai/features/transcription/recorder_controller.dart';
import 'package:one_ai/features/transcription/upload_queue.dart';
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
              gapH16,
              const _UnfinishedRecordingBanner(),
              const _PendingUploadsBanner(),
              const _PendingSharesBanner(),
              Row(children: [
                const Expanded(child: _SearchField()),
                gapW8,
                _AskAllButton(onTap: () => context.push(Routes.askAll)),
              ]),
              gapH16,
              const _TagRow(),
              gapH24,
              Expanded(
                child: switch (minutes) {
                  AsyncData(:final value) when value.isEmpty && ref.watch(searchQueryProvider).isNotEmpty => const _NoSearchResults(),
                  AsyncData(:final value) when value.isEmpty => const _EmptyNotes(),
                  AsyncData(:final value) => RefreshIndicator(
                      // The list is live; pull-to-refresh re-subscribes (network
                      // hiccup recovery) and refetches the quota pill, as v1 did.
                      onRefresh: () async {
                        ref.invalidate(minutesListProvider);
                        ref.invalidate(quotaProvider);
                        await ref.read(minutesListProvider.future);
                      },
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 80), // clear the FAB
                        itemCount: value.length + 1,
                        itemBuilder: (_, i) => i < value.length
                            ? Padding(padding: const EdgeInsets.only(bottom: 16), child: MinuteItemCard(item: value[i]))
                            : const _LoadMore(),
                      ),
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
          if (!premium) ...[gapW8, const _MinutesPill()],
          const Spacer(),
          _ActionButton(icon: Assets.messageIcon, label: context.l10n.giveFeedback, onTap: () async {
            await HapticFeedback.lightImpact();
            if (context.mounted) await showFeedbackDialog(context);
          }),
          gapW16,
          _ActionButton(icon: Assets.settingsIcon, label: context.l10n.settings, onTap: () { HapticFeedback.lightImpact(); context.push(Routes.settings); }),
        ],
      ),
    );
  }
}

/// A7-01 / S8-14: today's free minutes, always in view (industry complaint
/// #1 is hitting an invisible limit). Tap opens the paywall.
class _MinutesPill extends ConsumerWidget {
  const _MinutesPill();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(quotaProvider).valueOrNull;
    if (q == null || q.isUnlimited) return const SizedBox.shrink();
    final left = q.remainingMinutes;
    final low = q.remainingSeconds <= 60;
    return Semantics(
      button: true,
      label: context.l10n.freeMinutesLeftToday(left),
      child: InkWell(
        onTap: () async { await HapticFeedback.lightImpact(); await ref.read(paywallProvider).present(); },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: low ? const Color(0xFFFFEBEB) : TagChip.idleColor, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.timer_outlined, size: 16, color: low ? AppColors.destructiveRed : AppColors.brandBlue),
            gapW4,
            Text(context.l10n.minutesShort(left), style: TextStyle(color: low ? AppColors.destructiveRed : AppColors.brandBlue, fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      ),
    );
  }
}

/// Client-side search over title + transcript preview (S7-08, step 1 of
/// OQ-07). Same idle grey as the tag chips so it reads as part of the filter
/// row rather than a new element. Debounce is unnecessary: the filter is a
/// pure function over the already-loaded list.
class _SearchField extends ConsumerStatefulWidget {
  const _SearchField();
  @override
  ConsumerState<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends ConsumerState<_SearchField> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    if (query.isEmpty && _ctl.text.isNotEmpty) _ctl.clear(); // cleared elsewhere
    return SizedBox(
      height: 40,
      child: TextField(
        controller: _ctl,
        onChanged: ref.read(searchQueryProvider.notifier).set,
        textInputAction: TextInputAction.search,
        style: context.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: context.l10n.searchNotes,
          hintStyle: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[600]),
          suffixIcon: query.isEmpty
              ? null
              : IconButton(
                  tooltip: context.l10n.close,
                  icon: Icon(Icons.close, size: 18, color: Colors.grey[600]),
                  onPressed: () {
                    _ctl.clear();
                    ref.read(searchQueryProvider.notifier).clear();
                  },
                ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          filled: true,
          fillColor: TagChip.idleColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        ),
      ),
    );
  }
}

/// A7-02: a recording cut short by a crash / force-quit. The file is still on
/// disk; tapping sends it through the normal upload flow with the user's
/// default prompt settings. Dismiss deletes the marker (and the file).
final unfinishedRecordingProvider = FutureProvider<UnfinishedRecording?>((_) => UnfinishedRecording.load());

class _UnfinishedRecordingBanner extends ConsumerWidget {
  const _UnfinishedRecordingBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(unfinishedRecordingProvider).valueOrNull;
    if (r == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(children: [
            const Icon(Icons.history, size: 20, color: Color(0xFF9A6B00)),
            gapW8,
            Expanded(child: Text(l10n.unfinishedRecordingFound((r.seconds / 60).ceil()), style: context.textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B4A00)))),
            TextButton(
              onPressed: () async {
                await HapticFeedback.lightImpact();
                await UnfinishedRecording.clear();
                ref.invalidate(unfinishedRecordingProvider);
                if (!context.mounted) return;
                final files = r.usableFiles();
                final request = buildNewMinuteRequest(file: files.first, parts: files, settings: defaultPromptSettings(ref.read(languageSettingsProvider)), durationSeconds: r.seconds.toDouble());
                await runWithCreditGate(context, ref, requestedSeconds: r.seconds, () => context.push(Routes.audioProcessing, extra: AudioProcessingArgs(request: request)));
              },
              child: Text(l10n.recover, style: const TextStyle(color: AppColors.brandBlueAlt, fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: l10n.discard,
              icon: const Icon(Icons.close, size: 18, color: Color(0xFF9A6B00)),
              onPressed: () async {
                await UnfinishedRecording.clear();
                for (final p in r.paths) { try { File(p).deleteSync(); } on Object catch (_) {} }
                ref.invalidate(unfinishedRecordingProvider);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

/// S11-07: recordings waiting for the network (or a retry). Tap reopens the
/// processing screen for that recording.
class _PendingUploadsBanner extends ConsumerWidget {
  const _PendingUploadsBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(uploadQueueProvider);
    if (queue.isEmpty) return const SizedBox.shrink();
    final online = ref.watch(onlineProvider).valueOrNull ?? true;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () { HapticFeedback.lightImpact(); context.push(Routes.audioProcessing, extra: AudioProcessingArgs(request: queue.first)); },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(online ? Icons.cloud_upload_outlined : Icons.cloud_off_outlined, size: 20, color: const Color(0xFF9A6B00)),
              gapW8,
              Expanded(child: Text(online ? l10n.uploadsInProgress(queue.length) : l10n.uploadsWaitingForNetwork(queue.length), style: context.textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B4A00)))),
              const Icon(Icons.chevron_right, size: 20, color: Color(0xFF9A6B00)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Last row of the list: "Load more" while the live window is full (OQ-17).
/// Hidden while a search/tag filter is active — the filter runs over the
/// loaded window only, and growing it from here would surprise.
class _LoadMore extends ConsumerWidget {
  const _LoadMore();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMore = ref.watch(hasMoreMinutesProvider);
    final filtering = ref.watch(searchQueryProvider).isNotEmpty || ref.watch(selectedTagIdsProvider).isNotEmpty;
    if (!hasMore || filtering) return const SizedBox.shrink();
    final loading = ref.watch(minutesListProvider).isLoading;
    return Center(
      child: loading
          ? const Padding(padding: EdgeInsets.all(8), child: LoadingDots())
          : TextButton(
              onPressed: () { HapticFeedback.lightImpact(); ref.read(minutesWindowProvider.notifier).grow(); },
              child: Text(context.l10n.loadMoreNotes, style: const TextStyle(color: AppColors.brandBlueAlt)),
            ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();
  @override
  Widget build(BuildContext context) => Center(
        child: Text(context.l10n.noSearchResults, textAlign: TextAlign.center, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
      );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap});
  final String icon;
  /// Screen-reader name; the icon has no text (S9-03).
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(padding: const EdgeInsets.all(10), child: SvgPicture.asset(icon, width: 24, height: 24, excludeFromSemantics: true)),
        ),
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

/// S11-06b: files shared from another app that are still waiting their turn.
class _PendingSharesBanner extends ConsumerWidget {
  const _PendingSharesBanner();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(pendingIncomingSharesProvider).length;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: context.colorScheme.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => context.push(Routes.uploadFile),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(Icons.file_upload_outlined, color: context.colorScheme.primary),
              gapW12,
              Expanded(child: Text(context.l10n.sharedFilesWaiting(n), style: context.textTheme.bodyMedium)),
              TextButton(onPressed: () => context.push(Routes.uploadFile), child: Text(context.l10n.continueLabel)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// S11-01 entry point: the sparkle next to search opens "Ask your notes".
class _AskAllButton extends StatelessWidget {
  const _AskAllButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: context.l10n.askYourNotes,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: context.colorScheme.primary, borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          ),
        ),
      );
}

