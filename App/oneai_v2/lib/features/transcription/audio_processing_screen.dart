import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/failure_text.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/transcription/upload_queue.dart';
import 'package:one_ai/features/billing/paywall.dart';
import 'package:one_ai/features/credits/credit_gate_ui.dart';
import 'package:one_ai/features/credits/credits_provider.dart';
import 'package:one_ai/features/notifications/push_registrar.dart';
import 'package:one_ai/features/transcription/new_minute_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Port of v1 AudioProcessingScreen: the same five-step card, reward card
/// and "Show Results" button — but every step now reflects the real
/// NewMinuteFlow state instead of a timer, the close button really cancels,
/// and a failure shows the reason with Retry.
class AudioProcessingScreen extends ConsumerStatefulWidget {
  const AudioProcessingScreen({required this.args, super.key});
  final AudioProcessingArgs args;
  @override
  ConsumerState<AudioProcessingScreen> createState() => _AudioProcessingScreenState();
}

class _AudioProcessingScreenState extends ConsumerState<AudioProcessingScreen> {
  bool _celebrated = false;

  NewMinuteRequest get _req => widget.args.request;

  @override
  void initState() {
    super.initState();
    // S11-07: the queue keeps this flow alive after the screen is left and
    // retries when the network returns; the "leave while processing" dialog
    // below therefore only asks about cancelling, never about losing work.
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) ref.read(uploadQueueProvider.notifier).enqueue(_req); });
  }

  Future<void> _close() async {
    final state = ref.read(newMinuteFlowProvider(_req));
    if (state.isTerminal) {
      context.pop();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.cancelProcessing,
        confirmLabel: ctx.l10n.cancelProcessing,
        destructive: true,
        cancelLabel: ctx.l10n.back,
        content: Text(ctx.l10n.cancelProcessingConfirm, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
        onConfirm: () async {
          Navigator.of(ctx).pop();
          await ref.read(newMinuteFlowProvider(_req).notifier).cancel();
          if (context.mounted) context.pop();
        },
        // "Keep in background": go back to Home, the queue carries on.
        onCancel: () {
          Navigator.of(ctx).pop();
          if (context.mounted) context.pop();
        },
      ),
    );
  }

  /// OQ-18 (v1 behaviour): a "Premium Required" dialog first; "Go Premium"
  /// opens the paywall, "Cancel" leaves the failure card with its retry.
  Future<void> _premiumRequired() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.premiumRequired,
        content: Text(ctx.l10n.noFreeCreditsLeft, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
        cancelLabel: ctx.l10n.cancel,
        confirmLabel: ctx.l10n.goPremium,
        onCancel: () => Navigator.of(ctx).pop(),
        onConfirm: () async {
          Navigator.of(ctx).pop();
          await ref.read(paywallProvider).present();
        },
      ),
    );
  }

  Future<void> _showResults(String minuteId) async {
    await context.pushReplacement(Routes.transcriptionSummary, extra: SummaryArgs(minuteId: minuteId));
  }

  /// v1's Congratulation dialog on the first ever note → in-app review.
  Future<void> _celebrateIfFirst() async {
    if (_celebrated) return;
    _celebrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('FIRST_NOTE_CELEBRATED') ?? false) return;
      await prefs.setBool('FIRST_NOTE_CELEBRATED', true);
    } on Object catch (_) {
      return;
    }
    if (!mounted) return;
    // Best moment for the push prompt too: the user just saw a note finish.
    await ref.read(pushRegistrarProvider.notifier).requestPermission();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: ctx.l10n.congratulations,
        confirmLabel: ctx.l10n.sureIllRateIt,
        cancelLabel: ctx.l10n.notNow,
        content: Text(ctx.l10n.congratulationsMessage, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
        onConfirm: () async {
          Navigator.of(ctx).pop();
          final review = InAppReview.instance;
          if (await review.isAvailable()) await review.requestReview();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newMinuteFlowProvider(_req));
    final premium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final l10n = context.l10n;

    ref.listen(newMinuteFlowProvider(_req), (prev, next) {
      if (next is NewMinuteReady && prev is! NewMinuteReady) {
        _celebrateIfFirst();
        // OQ-19 (v1 behaviour): premium users, or anyone with no rewarded ad
        // on screen, go straight to the note; otherwise the "Show Results"
        // button stays so the ad card is not yanked away mid-view.
        final adOnScreen = !premium && ref.read(rewardedHookProvider).isReady;
        if (!adOnScreen) Future<void>.delayed(const Duration(milliseconds: 200), () { if (mounted) _showResults(next.id); });
      }
      if (next is NewMinuteFailed && next.isOutOfCredits) _premiumRequired();
    });

    return PopScope(
      canPop: state.isTerminal,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
      child: Scaffold(
        backgroundColor: context.colorScheme.surface,
        appBar: AppBar(
          backgroundColor: context.colorScheme.surface,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Row(children: [
            SvgPicture.asset(Assets.circularComplicationIcon, width: 32, height: 32),
            gapW8,
            Text(l10n.appName, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          actions: [IconButton(icon: const Icon(Icons.close), onPressed: () async { await HapticFeedback.lightImpact(); await _close(); })],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  gapH16,
                  _StepsCard(state: state),
                  gapH16,
                  if (state is NewMinuteFailed) ...[_FailureCard(state: state, request: _req), gapH16],
                  if (!premium && !state.isTerminal) ...[const _RewardCard(), gapH16],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(l10n.processingExplanation, textAlign: TextAlign.center, style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant)),
                  ),
                  gapH24,
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: state is NewMinuteReady
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () { HapticFeedback.lightImpact(); _showResults(state.id); },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
                    child: Text(l10n.showResults, style: context.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}

enum _StepStatus { pending, loading, done, error }

/// The five v1 steps, mapped onto the real state machine:
///   Processing audio = create + upload · Transcribing · Identifying speakers
///   (part of transcribing on the server) · Taking notes = summarizing ·
///   Finishing touches = ready.
class _StepsCard extends StatelessWidget {
  const _StepsCard({required this.state});
  final NewMinuteState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = [l10n.processingAudio, l10n.transcribing, l10n.identifyingSpeakers, l10n.takingNotes, l10n.finishingTouches];
    final (int active, bool failed, double? progress) = switch (state) {
      NewMinuteCreating() => (0, false, null),
      NewMinuteUploading(:final progress) => (0, false, progress.totalBytes == 0 ? null : progress.fraction),
      NewMinuteStarting() => (0, false, 1.0),
      NewMinuteProcessing(:final status) => switch (status) {
          MinuteStatus.queued => (1, false, null),
          MinuteStatus.transcribing => (2, false, null),
          _ => (3, false, null),
        },
      NewMinuteReady() => (5, false, null),
      NewMinuteCancelled() => (0, true, null),
      NewMinuteFailed(:final phase) => (switch (phase) { NewMinutePhase.creating || NewMinutePhase.uploading || NewMinutePhase.starting => 0, NewMinutePhase.processing => 2 }, true, null),
    };
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: context.colorScheme.outline.withAlpha(25))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final (i, label) in labels.indexed) ...[
              if (i > 0) gapH16,
              _StepRow(
                label: label,
                status: i < active ? _StepStatus.done : (i == active ? (failed ? _StepStatus.error : _StepStatus.loading) : _StepStatus.pending),
                progress: i == active ? progress : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.status, this.progress});
  final String label;
  final _StepStatus status;
  final double? progress;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          switch (status) {
            _StepStatus.pending => const SizedBox(width: 24, height: 24),
            _StepStatus.done => Container(width: 24, height: 24, decoration: BoxDecoration(color: context.colorScheme.primary, shape: BoxShape.circle), child: Icon(Icons.check, color: context.colorScheme.onPrimary, size: 16)),
            _StepStatus.error => Container(width: 24, height: 24, decoration: BoxDecoration(color: context.colorScheme.error, shape: BoxShape.circle), child: Icon(Icons.close, color: context.colorScheme.onError, size: 16)),
            _StepStatus.loading => SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  backgroundColor: context.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(context.colorScheme.primary),
                ),
              ),
          },
          gapW12,
          Expanded(child: Text(label, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
          if (status == _StepStatus.loading && progress != null)
            Text('${(progress! * 100).toInt()}%', style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.primary, fontWeight: FontWeight.w500)),
        ],
      );
}

class _FailureCard extends ConsumerWidget {
  const _FailureCard({required this.state, required this.request});
  final NewMinuteFailed state;
  final NewMinuteRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = state.serverFailure?.message.isNotEmpty == true ? state.serverFailure!.message : failureText(context, state.error);
    return Card(
      elevation: 0,
      color: context.colorScheme.errorContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(message, textAlign: TextAlign.center, style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onErrorContainer)),
            if (state.retryable && !(ref.watch(onlineProvider).valueOrNull ?? true)) ...[
              gapH12,
              Text(context.l10n.waitingForNetwork, textAlign: TextAlign.center, style: context.textTheme.bodySmall?.copyWith(color: context.colorScheme.onErrorContainer)),
            ] else if (state.retryable) ...[
              gapH12,
              TextButton(onPressed: () => ref.read(newMinuteFlowProvider(request).notifier).retry(), child: Text(context.l10n.retry)),
            ],
          ],
        ),
      ),
    );
  }
}

/// v1's "Earn a Free Credit While You Wait!" card. Shows only while a
/// rewarded ad is actually loaded — never a spinner waiting for one.
class _RewardCard extends ConsumerWidget {
  const _RewardCard();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewarded = ref.watch(rewardedHookProvider);
    if (!rewarded.isReady) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: context.colorScheme.outline.withAlpha(25))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SvgPicture.asset(Assets.giftFillIcon, width: 48, height: 48),
            gapH12,
            Text(l10n.earnFreeCreditWhileWaiting, textAlign: TextAlign.center, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            gapH12,
            Text(l10n.earnCreditBlurb, textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
            gapH12,
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () async {
                  await HapticFeedback.lightImpact();
                  final before = ref.read(quotaProvider).valueOrNull?.rewardBonus ?? 0;
                  final earned = await rewarded.show();
                  if (!context.mounted) return;
                  if (!earned) {
                    AppSnack.show(context, l10n.adNotCompleted);
                    return;
                  }
                  AppSnack.show(context, l10n.rewardOnItsWay);
                  final ok = await waitForRewardCreditWithRef(ref, before);
                  if (context.mounted && ok) AppSnack.show(context, l10n.rewardReceived(1));
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEA200), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(82))),
                child: Text('🔥 ${l10n.watchAdEarnCredit}', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
