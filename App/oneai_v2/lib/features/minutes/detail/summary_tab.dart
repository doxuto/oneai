import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/failure_text.dart';
import 'package:one_ai/data/models/ai_models.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/minutes/detail/ai_tools/ai_tools_row.dart';
import 'package:one_ai/features/minutes/detail/feedback_widget.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';
import 'package:one_ai/core/widgets/app_snack.dart';

/// v1 Summary tab (sections as plain bullet text), plus the blocks the new
/// artifacts add: action items, calendar events, and the AI tools row.
class SummaryTab extends ConsumerWidget {
  const SummaryTab({required this.detail, required this.scrollController, super.key});
  final MinuteDetail detail;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = detail.summary;
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(padding: EdgeInsets.only(bottom: 16), child: AdBannerSlot(placement: AdPlacement.summaryTab)),
          if (summary != null) ...summary.sections.map((s) => _SectionWidget(section: s)),
          if (detail.calendarEvents.isNotEmpty) ...[_CalendarEventsBlock(events: detail.calendarEvents), gapH24],
          if (detail.status == MinuteStatus.ready && detail.transcript != null) ...[
            _ActionItemsBlock(minuteId: detail.id),
            gapH24,
            AiToolsRow(detail: detail),
            gapH24,
          ],
          const SafeArea(minimum: EdgeInsets.only(bottom: 16), child: FeedbackWidget()),
        ],
      ),
    );
  }
}

/// v1 MinuteSectionWidget: bullets already carry "• " / "    ◦ " from the server.
class _SectionWidget extends StatelessWidget {
  const _SectionWidget({required this.section});
  final SummarySection section;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black)),
          gapH12,
          ...section.bullets.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 8),
                child: Row(children: [Expanded(child: Text(b, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black)))]),
              )),
          if (section.bullets.isEmpty) Text(section.title, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black)),
          gapH24,
        ],
      );
}

class _CalendarEventsBlock extends StatelessWidget {
  const _CalendarEventsBlock({required this.events});
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.calendarEvents, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black)),
          gapH12,
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF0F6FF), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text(e.resolvedAt != null ? _fmt(e.resolvedAt!) : e.datetime, style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                          if (e.participants.isNotEmpty) Text(e.participants.join(', '), style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        final start = e.resolvedAt ?? DateTime.now();
                        Add2Calendar.addEvent2Cal(Event(title: e.title, description: e.description, startDate: start, endDate: start.add(const Duration(hours: 1))));
                      },
                      child: Text(context.l10n.addToCalendar, style: const TextStyle(color: AppColors.brandBlueAlt)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );

  static String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.day}/${l.month}/${l.year}, ${two(l.hour)}:${two(l.minute)}';
  }
}

/// Action items + decisions. Generated on demand (one AI call, then cached);
/// ticks go to the server (`setActionItemDone`) so they follow the note to
/// every device; the box flips optimistically.
class _ActionItemsBlock extends ConsumerStatefulWidget {
  const _ActionItemsBlock({required this.minuteId});
  final String minuteId;
  @override
  ConsumerState<_ActionItemsBlock> createState() => _ActionItemsBlockState();
}

class _ActionItemsBlockState extends ConsumerState<_ActionItemsBlock> {
  bool _requested = false;

  Future<void> _toggle(ActionItem it) async {
    final ok = await ref.read(actionItemsProvider(widget.minuteId).notifier).setDone(it.id, !it.done);
    if (!ok && mounted) AppSnack.failure(context, ref.read(actionItemsProvider(widget.minuteId).notifier).lastTickError);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = Text(l10n.actionItems, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black));
    final detail = ref.watch(minuteDetailProvider(widget.minuteId)).valueOrNull;
    final already = detail?.hasArtifact(ArtifactKind.actionItems) ?? false;
    if (!_requested && !already) {
      return Row(
        children: [
          title,
          const Spacer(),
          TextButton(onPressed: () => setState(() => _requested = true), child: Text(l10n.generate, style: const TextStyle(color: AppColors.brandBlueAlt))),
        ],
      );
    }
    final items = ref.watch(actionItemsProvider(widget.minuteId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          title,
          const Spacer(),
          if (items.hasValue)
            TextButton(onPressed: () => ref.read(actionItemsProvider(widget.minuteId).notifier).regenerate(), child: Text(l10n.regenerate, style: const TextStyle(color: AppColors.brandBlueAlt))),
        ]),
        gapH12,
        switch (items) {
          AsyncData(:final value) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (value.data.items.isEmpty && value.data.decisions.isEmpty) Text(l10n.noActionItems, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
                for (final it in value.data.items)
                  CheckboxListTile(
                    value: it.done,
                    onChanged: (_) => _toggle(it),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.brandBlueAlt,
                    title: Text(it.text, style: context.textTheme.bodyMedium?.copyWith(decoration: it.done ? TextDecoration.lineThrough : null)),
                    subtitle: (it.owner != null || it.due != null)
                        ? Text([if (it.owner != null) it.owner!, if (it.due != null) it.due!].join(' · '), style: context.textTheme.bodySmall?.copyWith(color: Colors.grey[600]))
                        : null,
                  ),
                if (value.data.decisions.isNotEmpty) ...[
                  gapH12,
                  Text(l10n.decisions, style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.black)),
                  gapH8,
                  for (final d in value.data.decisions) Padding(padding: const EdgeInsets.only(bottom: 8, left: 8), child: Text('• $d', style: context.textTheme.bodyMedium?.copyWith(color: Colors.black))),
                ],
              ],
            ),
          AsyncError(:final error) => Text(failureText(context, error), style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.error)),
          _ => const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))),
        },
      ],
    );
  }
}
