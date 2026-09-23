import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:one_ai/core/config/assets.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/router/route_args.dart';
import 'package:one_ai/core/router/routes.dart';
import 'package:one_ai/core/theme/gaps.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/features/credits/credit_gate_ui.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/transcription/consent_notice.dart';
import 'package:one_ai/features/transcription/new_minute_request_builder.dart';
import 'package:one_ai/features/transcription/prompt_language_sheet.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/credits/credits_provider.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/features/transcription/recorder_controller.dart';

/// Port of v1 RecordAudioScreen: same rings, button, timer, prompt button,
/// exit warning. The recorder lives in RecorderController; the wave rings
/// now also scale with the live amplitude.
class RecordAudioScreen extends ConsumerStatefulWidget {
  const RecordAudioScreen({super.key});
  @override
  ConsumerState<RecordAudioScreen> createState() => _RecordAudioScreenState();
}

class _RecordAudioScreenState extends ConsumerState<RecordAudioScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(duration: const Duration(milliseconds: 3000), vsync: this)..repeat();
  static const _waveOpacities = [1.0, 0.8, 0.6, 0.4];
  PromptSettings? _settings;

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  PromptSettings _currentSettings() => _settings ??= defaultPromptSettings(ref.read(languageSettingsProvider));

  Future<void> _openPromptSheet() async {
    final result = await PromptLanguageSheet.show(context, _currentSettings());
    if (result != null) setState(() => _settings = result);
  }

  Future<void> _showExitWarning() => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StyledDialog(
          title: ctx.l10n.warning,
          titleIcon: SvgPicture.asset(Assets.warningTriangleIcon, width: 18, height: 18, colorFilter: const ColorFilter.mode(Color(0xFFF8C307), BlendMode.srcIn)),
          confirmLabel: ctx.l10n.exit,
          destructive: true,
          content: Text(ctx.l10n.exitRecordingWarning, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
          onConfirm: () async {
            await ref.read(recorderProvider.notifier).discard();
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            if (context.mounted) context.pop();
          },
        ),
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    ref.read(recorderProvider.notifier)
      ..notificationTitle = l10n.appName
      ..notificationText = l10n.recordingInProgress;
  }

  /// First recording on this device: a one-time consent reminder (S11-12).
  /// "Got it" starts the recording; "Share notice" opens the share sheet first.
  Future<bool> _consentOk() async {
    if (await ConsentNotice.isAcknowledged()) return true;
    if (!mounted) return false;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: l10n.consentTitle,
        titleIcon: Icon(Icons.record_voice_over_outlined, size: 18, color: ctx.colorScheme.primary),
        content: Text(l10n.consentBody, style: ctx.textTheme.bodyMedium),
        confirmLabel: l10n.gotIt,
        onConfirm: () => Navigator.of(ctx).pop(true),
        cancelLabel: l10n.recordingNotice,
        onCancel: () async {
          Navigator.of(ctx).pop(true);
          await SharePlus.instance.share(ShareParams(text: l10n.recordingNoticeText, subject: l10n.recordingNotice));
        },
      ),
    );
    if (ok != true) return false;
    await ConsentNotice.acknowledge();
    return true;
  }

  Future<void> _transcribe() async {
    final seconds = ref.read(recorderProvider).seconds;
    await runWithCreditGate(context, ref, requestedSeconds: seconds, () async {
      final parts = await ref.read(recorderProvider.notifier).finish();
      if (parts == null || parts.isEmpty || !mounted) return;
      final request = buildNewMinuteRequest(file: parts.first, parts: parts, settings: _currentSettings(), durationSeconds: seconds.toDouble());
      await context.push(Routes.audioProcessing, extra: AudioProcessingArgs(request: request));
    });
  }

  @override
  Widget build(BuildContext context) {
    final rec = ref.watch(recorderProvider);
    final l10n = context.l10n;
    final primary = context.colorScheme.primary;
    final isRecording = rec.phase == RecordingPhase.recording;
    final isInitial = rec.phase == RecordingPhase.initial;

    // Free plan: stop at what is left today (server would refuse more).
    final quota = ref.watch(quotaProvider).valueOrNull;
    final premium = ref.watch(isPremiumProvider).valueOrNull ?? false;
    final capSeconds = premium ? (quota?.maxDurationSeconds ?? 14400) : (quota?.maxRecordingSeconds ?? 600);
    ref.listen(recorderProvider.select((s) => s.seconds), (_, secs) async {
      if (secs >= capSeconds && ref.read(recorderProvider).phase == RecordingPhase.recording) {
        await ref.read(recorderProvider.notifier).pause();
        if (context.mounted) AppSnack.show(context, premium ? l10n.recordingTooLong((capSeconds / 60).round()) : l10n.freeMinutesUsedUp);
      }
    });
    ref.listen(recorderProvider.select((s) => s.resumedAfterInterruption), (_, resumed) {
      if (resumed) {
        AppSnack.show(context, l10n.recordingResumed);
        ref.read(recorderProvider.notifier).ackResumed();
      }
    });
    ref.listen(recorderProvider.select((s) => s.permissionDenied), (_, denied) {
      if (denied) AppSnack.show(context, l10n.microphonePermissionNeeded);
    });

    return PopScope(
      canPop: isInitial,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _showExitWarning();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            tooltip: context.l10n.back,
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await HapticFeedback.lightImpact();
              if (!context.mounted) return;
              if (isInitial) {
                context.pop();
              } else {
                await _showExitWarning();
              }
            },
          ),
          title: Row(children: [
            SvgPicture.asset(Assets.circularComplicationIcon, width: 32, height: 32),
            gapW8,
            Text(l10n.oneAi, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ]),
          centerTitle: false,
          actions: [
            // A7-03 / S11-12: one tap to tell the room it is being recorded.
            IconButton(
              tooltip: l10n.recordingNotice,
              icon: const Icon(Icons.campaign_outlined),
              onPressed: () async {
                await HapticFeedback.lightImpact();
                await SharePlus.instance.share(ShareParams(text: l10n.recordingNoticeText, subject: l10n.recordingNotice));
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    const SizedBox(height: 60),
                    Center(
                      child: SizedBox(
                        width: 220,
                        height: 220,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ...List.generate(4, (index) => AnimatedBuilder(
                                  animation: _wave,
                                  builder: (context, _) {
                                    final value = (_wave.value + index * 0.2) % 1.0;
                                    final size = 120.0 + value * (100.0 + 40.0 * rec.amplitude);
                                    final opacity = isRecording ? (1.0 - value) * _waveOpacities[index] : 0.0;
                                    return Opacity(
                                      opacity: opacity,
                                      child: Container(
                                        width: size,
                                        height: size,
                                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primary.withAlpha(128), width: 1.5)),
                                      ),
                                    );
                                  },
                                )),
                            GestureDetector(
                              onTap: () async {
                                await HapticFeedback.lightImpact();
                                if (isInitial && !await _consentOk()) return;
                                await ref.read(recorderProvider.notifier).toggle();
                              },
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isRecording ? primary : Colors.white,
                                  border: Border.all(color: primary, width: rec.phase == RecordingPhase.paused ? 2 : 1),
                                ),
                                child: Center(
                                  child: SvgPicture.asset(
                                    Assets.microphoneFilledIcon,
                                    width: 36,
                                    height: 36,
                                    colorFilter: ColorFilter.mode(isRecording ? Colors.white : primary, BlendMode.srcIn),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    gapH24,
                    Text(
                      switch (rec.phase) {
                        RecordingPhase.initial => l10n.tapToStartRecording,
                        RecordingPhase.recording => l10n.tapToStopRecording,
                        RecordingPhase.paused => rec.interrupted ? l10n.recordingInterrupted : l10n.recordingPaused,
                      },
                      style: context.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Opacity(
                        opacity: isInitial ? 0.0 : 1.0,
                        child: Text(
                          _clock(rec.seconds),
                          style: context.textTheme.bodyMedium?.copyWith(color: isRecording ? primary : Colors.grey[500]),
                        ),
                      ),
                    ),
                    // A7-01 / S8-14: what is left today, always visible on the
                    // free plan, so nobody hits the ceiling by surprise.
                    if (!premium && quota != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l10n.freeMinutesLeftToday(((capSeconds - (isInitial ? 0 : rec.seconds)).clamp(0, 1 << 30) / 60).ceil()),
                          style: context.textTheme.bodySmall?.copyWith(color: (capSeconds - rec.seconds) <= 60 ? AppColors.destructiveRed : Colors.grey[600]),
                        ),
                      ),
                    const SizedBox(height: 60),
                    SizedBox(
                      height: 48,
                      child: TextButton.icon(
                        onPressed: () async {
                          await HapticFeedback.lightImpact();
                          await _openPromptSheet();
                        },
                        iconAlignment: IconAlignment.end,
                        icon: SvgPicture.asset(Assets.settingsIcon, width: 24, height: 24, colorFilter: ColorFilter.mode(primary, BlendMode.srcIn)),
                        label: Text(l10n.promptAndLanguage),
                        style: TextButton.styleFrom(foregroundColor: primary, padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Visibility(
                    visible: rec.phase == RecordingPhase.paused,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        _transcribe();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                      ),
                      child: Text(creditGateLabel(context, ref, l10n.transcribeAndSummarize)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
