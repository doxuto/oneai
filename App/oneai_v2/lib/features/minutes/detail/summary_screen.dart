import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/format.dart';
import 'package:one_ai/core/widgets/state_views.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/minutes/detail/audio_player_controller.dart';
import 'package:one_ai/features/minutes/detail/chat_tab.dart';
import 'package:one_ai/features/minutes/detail/minute_detail_controller.dart';
import 'package:one_ai/features/minutes/detail/summary_tab.dart';
import 'package:one_ai/features/minutes/detail/transcript_tab.dart';
import 'package:one_ai/features/minutes/detail/transcript_tab_selector.dart';
import 'package:one_ai/features/minutes/share/share_hooks.dart';

/// Port of v1 TranscriptionSummaryScreen: "Back" app bar with share menu,
/// title, "date • duration", three tabs, mini play FAB that expands into the
/// control dashboard. Exit shows the `summary_exit` interstitial (v1 skipped
/// it on one branch by mistake — OQ-11).
class TranscriptionSummaryScreen extends ConsumerStatefulWidget {
  const TranscriptionSummaryScreen({required this.args, super.key});
  final SummaryArgs args;
  @override
  ConsumerState<TranscriptionSummaryScreen> createState() => _State();
}

class _State extends ConsumerState<TranscriptionSummaryScreen> {
  late TranscriptTab _tab = TranscriptTab.values[widget.args.initialTab.clamp(0, 2)];
  final _summaryScroll = ScrollController();
  final _transcriptScroll = ScrollController();
  final _chatScroll = ScrollController();

  String get _id => widget.args.minuteId;

  @override
  void dispose() {
    _summaryScroll.dispose();
    _transcriptScroll.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _exit() async {
    await ref.read(interstitialHookProvider).maybeShow(AdPlacement.summaryExit);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(minuteDetailProvider(_id));
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _exit(); },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.brandBlueAlt), onPressed: () async { await HapticFeedback.lightImpact(); await _exit(); }),
          title: Text(l10n.back, style: context.textTheme.titleMedium?.copyWith(color: AppColors.brandBlueAlt)),
          titleSpacing: 0,
          centerTitle: false,
          actions: [if (detail.valueOrNull case final d?) _ShareMenu(detail: d)],
        ),
        body: switch (detail) {
          AsyncData(:final value) => _body(context, value),
          AsyncError(:final error) => ErrorState(error: error, onRetry: () => ref.invalidate(minuteDetailProvider(_id))),
          _ => const LoadingState(),
        },
        floatingActionButton: (_tab == TranscriptTab.minutes || _tab == TranscriptTab.transcript) && (detail.valueOrNull?.canPlaySource ?? false)
            ? _PlayerFab(minuteId: _id, sourcePath: detail.requireValue.sourcePath!)
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _body(BuildContext context, MinuteDetail d) {
    final sub = [formatDateTime(d.summaryInfo.createdAt), if (d.sourceType == SourceType.audio) formatDurationLong(d.summaryInfo.durationSeconds ?? d.transcript?.durationSeconds)].join(' • ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.summary?.title ?? d.summaryInfo.title, style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          gapH8,
          Text(sub, style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600])),
          gapH16,
          TranscriptTabSelector(selected: _tab, onSelected: (t) => setState(() => _tab = t)),
          gapH16,
          Expanded(
            child: switch (_tab) {
              TranscriptTab.minutes => d.status == MinuteStatus.ready ? SummaryTab(detail: d, scrollController: _summaryScroll) : _NotReady(detail: d),
              TranscriptTab.transcript => TranscriptTab(detail: d, scrollController: _transcriptScroll),
              TranscriptTab.chat => d.status == MinuteStatus.ready ? ChatTab(minuteId: d.id, scrollController: _chatScroll) : _NotReady(detail: d),
            },
          ),
        ],
      ),
    );
  }
}

/// A note opened from a notification while still processing, or one that failed.
class _NotReady extends StatelessWidget {
  const _NotReady({required this.detail});
  final MinuteDetail detail;
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = switch (detail.status) {
      MinuteStatus.failed => detail.failure?.message ?? l10n.statusFailed,
      MinuteStatus.cancelled => l10n.statusCancelled,
      _ => l10n.noteNotReady,
    };
    return EmptyState(title: title, icon: Icon(detail.status == MinuteStatus.failed ? Icons.error_outline : Icons.hourglass_top, size: 40, color: Colors.grey));
  }
}

class _ShareMenu extends ConsumerWidget {
  const _ShareMenu({required this.detail});
  final MinuteDetail detail;

  static const _divider = PopupMenuItem<Never>(height: 1, enabled: false, padding: EdgeInsets.zero, child: Divider(color: AppColors.dividerGrey, height: 1));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return PopupMenuButton<ShareOption>(
      onSelected: (o) async {
        await ref.read(minuteSharerProvider).share(context, detail, o);
        await ref.read(interstitialHookProvider).maybeShow(AdPlacement.afterShare);
      },
      tooltip: l10n.share,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(context.appTheme.cardRadius)),
      offset: const Offset(0, 8),
      color: Colors.white,
      elevation: 4,
      icon: SvgPicture.asset(Assets.shareIcon, width: 24, height: 24, colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn)),
      itemBuilder: (context) => [
        _item(context, ShareOption.notesAsPdf, l10n.shareNotesAsPdf, Assets.pdfIcon),
        _divider,
        _item(context, ShareOption.notesAsText, l10n.shareNotesAsText, Assets.textIcon),
        _divider,
        _item(context, ShareOption.transcriptAsPdf, l10n.shareTranscriptAsPdf, Assets.pdfIcon),
        _divider,
        _item(context, ShareOption.transcriptAsText, l10n.shareTranscriptAsText, Assets.noteTextIcon),
        if (detail.canPlaySource) ...[_divider, _item(context, ShareOption.audioFile, l10n.shareAudioFile, Assets.audioLinesIcon)],
      ],
    );
  }

  PopupMenuItem<ShareOption> _item(BuildContext context, ShareOption o, String text, String icon) => PopupMenuItem<ShareOption>(
        value: o,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(text, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w400)),
            SvgPicture.asset(icon, width: 20, height: 20, colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn)),
          ],
        ),
      );
}

/// v1's mini play FAB → control dashboard (speed, ±10s, play/pause, close, slider).
class _PlayerFab extends ConsumerWidget {
  const _PlayerFab({required this.minuteId, required this.sourcePath});
  final String minuteId;
  final String sourcePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(audioPlayerProvider(minuteId));
    final ctl = ref.read(audioPlayerProvider(minuteId).notifier);
    if (!p.expanded || p.phase != PlayerPhase.ready) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 100),
        child: SizedBox(
          width: 42,
          height: 42,
          child: FloatingActionButton(
            onPressed: () async { await HapticFeedback.lightImpact(); await ctl.open(sourcePath); },
            backgroundColor: AppColors.brandBlueAlt,
            elevation: 2,
            shape: const CircleBorder(),
            mini: true,
            child: p.phase == PlayerPhase.loading
                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white), strokeWidth: 2.2)))
                : SvgPicture.asset(Assets.playIcon, width: 24, height: 24, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
          ),
        ),
      );
    }
    final maxMs = p.duration.inMilliseconds.toDouble();
    final posMs = p.position.inMilliseconds.toDouble().clamp(0.0, maxMs == 0 ? 0.0 : maxMs);
    return Padding(
      padding: const EdgeInsets.only(bottom: 100, left: 32),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: () async { await HapticFeedback.lightImpact(); await ctl.cycleSpeed(); }, child: Text('${p.speed.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.brandBlueAlt))),
                IconButton(icon: const Icon(Icons.replay_10, color: AppColors.brandBlueAlt), onPressed: () async { await HapticFeedback.lightImpact(); await ctl.seekRelative(const Duration(seconds: -10)); }),
                IconButton(icon: Icon(p.playing ? Icons.pause : Icons.play_arrow, color: AppColors.brandBlueAlt, size: 32), onPressed: () async { await HapticFeedback.lightImpact(); await ctl.toggle(); }),
                IconButton(icon: const Icon(Icons.forward_10, color: AppColors.brandBlueAlt), onPressed: () async { await HapticFeedback.lightImpact(); await ctl.seekRelative(const Duration(seconds: 10)); }),
                IconButton(icon: const Icon(Icons.close, color: AppColors.brandBlueAlt), onPressed: () { HapticFeedback.lightImpact(); ctl.collapse(); }),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(_mmss(p.position), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  Expanded(
                    child: Slider(
                      value: posMs,
                      max: maxMs == 0 ? 1 : maxMs,
                      onChanged: (v) => ctl.seek(Duration(milliseconds: v.toInt())),
                    ),
                  ),
                  Text(_mmss(p.duration), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _mmss(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}
