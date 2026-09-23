import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/format.dart';
import 'package:one_ai/core/widgets/loading_dots.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/minutes/detail/audio_player_controller.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';
import 'package:one_ai/features/minutes/detail/translate_toggle.dart';
import 'package:one_ai/data/repositories/ai_repository.dart';

/// v1 Transcript tab (speaker rows with coloured avatars, timestamps, rename
/// on tap) plus what the new data adds: a chapter strip that seeks the
/// player, the segment now playing highlighted, talk-time per speaker, and
/// a notice instead of a player when the source audio has expired.
class TranscriptTab extends ConsumerWidget {
  const TranscriptTab({required this.detail, required this.scrollController, super.key});
  final MinuteDetail detail;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transcript = detail.transcript;
    final translateTo = ref.watch(translateToProvider(detail.id));
    final player = ref.watch(audioPlayerProvider(detail.id));
    final now = player.expanded ? player.positionSeconds : null;
    final speakerOrder = <String>[];
    for (final s in transcript?.segments ?? const <TranscriptSegment>[]) {
      if (!speakerOrder.contains(s.speakerId)) speakerOrder.add(s.speakerId);
    }
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(bottom: 16), child: AdBannerSlot(placement: AdPlacement.transcriptTab)),
          if (detail.sourceState == SourceState.expired) ...[_ExpiredNotice(), gapH16],
          if (detail.talkTime.length > 1) ...[_TalkTimeBar(talkTime: detail.talkTime, speakerOrder: speakerOrder), gapH16],
          if (detail.sourceType == SourceType.audio && transcript != null) ...[_ChaptersStrip(detail: detail, positionSeconds: now), gapH16],
          if (transcript != null) ...[TranslateToggle(minuteId: detail.id), gapH16],
          if (transcript != null && translateTo != null)
            TranslatedBody(minuteId: detail.id, part: TranslatePart.transcript, language: translateTo)
          else if (transcript != null)
            for (final seg in transcript.segments)
              _SegmentRow(
                minuteId: detail.id,
                segment: seg,
                label: detail.speakerLabelFor(seg.speakerId),
                colorIndex: speakerOrder.indexOf(seg.speakerId),
                isPlaying: now != null && now >= seg.startSeconds && now < seg.endSeconds,
                canSeek: detail.canPlaySource,
              ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}

class _ExpiredNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Color(0xFFB4711A)),
          gapW8,
          Expanded(child: Text(context.l10n.audioExpired, style: context.textTheme.bodySmall)),
        ]),
      );
}

class _TalkTimeBar extends StatelessWidget {
  const _TalkTimeBar({required this.talkTime, required this.speakerOrder});
  final List<TalkTime> talkTime;
  final List<String> speakerOrder;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(children: [
                for (final t in talkTime)
                  Expanded(flex: (t.share * 1000).round().clamp(1, 1000), child: ColoredBox(color: speakerColor(speakerOrder.indexOf(t.speakerId)))),
              ]),
            ),
          ),
          gapH8,
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final t in talkTime)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: speakerColor(speakerOrder.indexOf(t.speakerId)), shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('${t.label} ${(t.share * 100).round()}%', style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                ]),
            ],
          ),
        ],
      );
}

/// Chapters load lazily (one AI call, cached). Until generated, a single
/// "Chapters" chip offers it; a PDF never shows this strip.
class _ChaptersStrip extends ConsumerStatefulWidget {
  const _ChaptersStrip({required this.detail, required this.positionSeconds});
  final MinuteDetail detail;
  final double? positionSeconds;
  @override
  ConsumerState<_ChaptersStrip> createState() => _ChaptersStripState();
}

class _ChaptersStripState extends ConsumerState<_ChaptersStrip> {
  bool _requested = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.detail.id;
    if (!_requested && !widget.detail.hasArtifact(ArtifactKind.chapters)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.auto_awesome, size: 16, color: AppColors.brandBlue),
          label: Text(context.l10n.generateChapters, style: const TextStyle(color: AppColors.brandBlue)),
          backgroundColor: const Color(0xFFEDF4FF),
          side: BorderSide.none,
          onPressed: () => setState(() => _requested = true),
        ),
      );
    }
    final chapters = ref.watch(chaptersProvider(id));
    return switch (chapters) {
      AsyncData(:final value) => SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: value.data.chapters.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = value.data.chapters[i];
              final pos = widget.positionSeconds;
              final active = pos != null && pos >= c.startSeconds && pos < c.endSeconds;
              return ChoiceChip(
                selected: active,
                showCheckmark: false,
                label: Text('${formatClock(c.startSeconds)}  ${c.title}', style: TextStyle(color: active ? Colors.white : AppColors.brandBlue, fontSize: 13)),
                selectedColor: AppColors.brandBlue,
                backgroundColor: const Color(0xFFEDF4FF),
                side: BorderSide.none,
                onSelected: widget.detail.canPlaySource
                    ? (_) async {
                        await HapticFeedback.lightImpact();
                        final p = ref.read(audioPlayerProvider(id).notifier);
                        if (!ref.read(audioPlayerProvider(id)).expanded) await p.open(widget.detail.sourcePath!);
                        await p.seekSeconds(c.startSeconds);
                      }
                    : null,
              );
            },
          ),
        ),
      AsyncError(:final error) => Text(context.l10n.somethingWentWrong, style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.error)),
      _ => const SizedBox(height: 36, child: Align(alignment: Alignment.centerLeft, child: LoadingDots(size: 6, spacing: 4))),
    };
  }
}

/// v1's five speaker colours, by order of first appearance.
Color speakerColor(int index) => switch (index % 5) {
      0 => Colors.purple,
      1 => Colors.red,
      2 => Colors.blue,
      3 => Colors.green,
      _ => Colors.orange,
    };

class _SegmentRow extends ConsumerWidget {
  const _SegmentRow({required this.minuteId, required this.segment, required this.label, required this.colorIndex, required this.isPlaying, required this.canSeek});
  final String minuteId;
  final TranscriptSegment segment;
  final String label;
  final int colorIndex;
  final bool isPlaying;
  final bool canSeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speakers = ref.watch(speakersProvider(minuteId));
    final renaming = speakers.isLoading && speakers.hasValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: speakerColor(colorIndex < 0 ? 0 : colorIndex), shape: BoxShape.circle),
            child: Center(child: Text('${colorIndex + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
          ),
          gapW12,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (renaming)
                    const LoadingDots(dotCount: 3)
                  else
                    TextButton(
                      onPressed: () => _rename(context, ref),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text(label, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  gapW8,
                  InkWell(
                    onTap: canSeek ? () => ref.read(audioPlayerProvider(minuteId).notifier).seekSeconds(segment.startSeconds) : null,
                    child: Text(formatClock(segment.startSeconds), style: context.textTheme.bodySmall?.copyWith(color: canSeek ? AppColors.brandBlueAlt : Colors.grey[600])),
                  ),
                ]),
                gapH8,
                Text(segment.text, style: context.textTheme.bodyMedium?.copyWith(backgroundColor: isPlaying ? const Color(0xFFE6F0FF) : null)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _rename(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: label);
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
              child: TextField(controller: controller, autofocus: true, decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12))),
            ),
          ],
        ),
        onConfirm: () async {
          Navigator.of(ctx).pop();
          final ok = await ref.read(speakersProvider(minuteId).notifier).rename(segment.speakerId, controller.text);
          if (!ok && context.mounted) AppSnack.show(context, context.l10n.failedToUpdateSpeaker);
        },
      ),
    );
  }
}
