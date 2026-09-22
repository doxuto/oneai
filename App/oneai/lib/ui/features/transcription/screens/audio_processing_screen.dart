import 'dart:async';

import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/config/constants.dart';
import 'package:codebase_ai/data/repositories/oneai_repository.dart';
import 'package:codebase_ai/data/services/admob/interstitial_ad_service.dart';
import 'package:codebase_ai/data/services/admob/reward_ad_service.dart';
import 'package:codebase_ai/domain/models/transcription_model.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/widgets/language_selector.dart';
import 'package:codebase_ai/utils/extensions.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

class AudioProcessingScreen extends StatefulWidget {
  const AudioProcessingScreen({super.key});

  @override
  State<AudioProcessingScreen> createState() => _AudioProcessingScreenState();
}

class _ProcessingStepState {
  static const loading = 0;
  static const completed = 1;
  static const error = 2;
}

class _ProcessingStep {
  final String label;
  int state = _ProcessingStepState.loading;
  double progress = 0;

  _ProcessingStep({required this.label});
}

class _AudioProcessingScreenState extends State<AudioProcessingScreen> {
  final List<_ProcessingStep> _steps = [];
  Timer? _progressTimer;
  final _log = Logger('AudioProcessingScreen');

  // Store the incoming data
  String? _audioPath;
  String? _audioLanguage;
  String? _summaryLanguage;
  String? _recordingContext;
  String? _keywords;
  bool _transcribeStarted = false;
  String? _error;
  bool _shouldSpeedUp = false;
  String? _youtubeLink;
  late String _minuteId;

  bool _isPremium = false;
  bool _isProcessSucceeded = false;

  @override
  void initState() {
    super.initState();
    _startProcessingSimulation();

    Future.microtask(() async {
      final isPre = await isPremium();
      if (!mounted) return;
      setState(() {
        _isPremium = isPre;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_steps.isEmpty) {
      _initializeSteps();
    }
    // Only parse once
    if (!_transcribeStarted) {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map) {
        _audioPath = extra['audioPath'] as String?;
        _audioLanguage = extra['audioLanguage'] as String?;
        _summaryLanguage = extra['summaryLanguage'] as String?;
        _recordingContext = extra['recordingContext'] as String?;
        _keywords = extra['keywords'] as String?;
        // Handle YouTube link
        _youtubeLink = extra['youtubeLink'] as String?;
      }
      _startTranscription();
      _transcribeStarted = true;
    }
  }

  Future<void> _startTranscription() async {
    final minuteUseCase = context.read<MinuteUseCase>();
    late Result<Transcription> result;
    final audioLanguageCode = (_audioLanguage != null) ? Language.values.byName(_audioLanguage!).languageCode : null;
    final summaryLanguageCode =
        (_summaryLanguage != null) ? Language.values.byName(_summaryLanguage!).languageCode : null;
    if (_youtubeLink != null && _youtubeLink!.isNotEmpty) {
      result = await minuteUseCase.transcribeYoutube(
        youtubeUrl: _youtubeLink!,
        audioLanguage: audioLanguageCode,
        summaryLanguage: summaryLanguageCode,
      );
    } else if (_audioPath != null && _audioPath!.isNotEmpty) {
      result = await minuteUseCase.transcribe(
        filePath: _audioPath!,
        audioLanguage: audioLanguageCode,
        summaryLanguage: summaryLanguageCode,
        keywords: _keywords,
        description: _recordingContext,
      );
    } else {
      return;
    }
    if (!mounted) return;
    switch (result) {
      case Ok(value: final transcription):
        _minuteId = transcription.minuteId!;

        // getSpeakers for minuteId
        await context.read<OneAiRepository>().getSpeakers(minuteId: _minuteId);

        if (context.mounted) {
          setState(() {
            _shouldSpeedUp = true;
          });
        }
        break;
      case Error(error: final error):
        setState(() {
          _error = error.toString();
          if (_steps.isNotEmpty) {
            _steps.firstWhere((step) => step.state == _ProcessingStepState.loading, orElse: () => _steps.last).state =
                _ProcessingStepState.error;
          }
        });
        _progressTimer?.cancel();

        if (mounted) {
          _log.severe('_startTranscription error: $error');

          switch (error) {
            case DioException _:
              switch (error.response?.statusCode) {
                case 402:
                  final result = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder:
                        (ctx) => AlertDialog(
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [Text('Premium Required', style: context.textTheme.titleLarge)],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'You have no free credits left. Please upgrade your plan.',
                                textAlign: TextAlign.center,
                                style: context.textTheme.bodyMedium,
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
                                        Navigator.of(ctx).pop(false);
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
                                        Navigator.of(ctx).pop(true);
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                                        ),
                                      ),
                                      child: Text(
                                        'Go Premium',
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
                  if (result ?? false) {
                    await RevenueCatUI.presentPaywallIfNeeded(Constants.entitlementId);
                  }
                  break;
                default:
                  // Show error snackbar
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Something went wrong, please try later'),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                  break;
              }
              break;
            default:
              // Show error snackbar
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Something went wrong, please try later'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              );
              break;
          }
        }
        break;
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _initializeSteps() {
    _steps.addAll([
      _ProcessingStep(label: context.loc.processingAudio),
      _ProcessingStep(label: context.loc.transcribing),
      _ProcessingStep(label: context.loc.identifyingSpeakers),
      _ProcessingStep(label: context.loc.takingNotes),
      _ProcessingStep(label: context.loc.finishingTouches),
    ]);
  }

  void _startProcessingSimulation() {
    int currentStepIndex = 0;
    _shouldSpeedUp = false;

    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final speed = _shouldSpeedUp ? 0.01 : 0.001;

      if (currentStepIndex >= _steps.length) {
        timer.cancel();
        // Only navigate if transcription succeeded (_shouldSpeedUp is true and no error)
        if (_shouldSpeedUp && _error == null) {
          if (_isPremium || !context.isFullscreenAdInProgress()) {
            Future.delayed(const Duration(microseconds: 200), () async {
              if (mounted) {
                await navigateToSummary();
              }
            });
          } else {
            setState(() {
              _isProcessSucceeded = true;
            });
          }
        } else if (!_shouldSpeedUp && _error == null) {
          // If we reach the end and transcribe did not return, show error
          setState(() {
            _error = 'Transcription did not complete in time.';
            if (_steps.isNotEmpty) {
              _steps.last.state = _ProcessingStepState.error;
            }
          });
        }
        return;
      }

      setState(() {
        final currentStep = _steps[currentStepIndex]..progress += speed;

        if (currentStep.progress >= 1.0) {
          currentStep
            ..state = _ProcessingStepState.completed
            ..progress = 1.0;

          currentStepIndex++;

          if (currentStepIndex < _steps.length) {
            _steps[currentStepIndex].state = _ProcessingStepState.loading;
          }
        }
      });
    });
  }

  Future<void> navigateToSummary() async {
    if (!context.mounted) return;
    context.go(Routes.transcriptionSummary, extra: _minuteId);
  }


  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.colorScheme.surface,
    appBar: AppBar(
      backgroundColor: context.colorScheme.surface,
      elevation: 0,
      title: Row(
        children: [
          SvgPicture.asset(Assets.circularComplicationIcon, width: 32, height: 32),
          gapW8,
          Text(context.loc.appName, style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            await HapticFeedback.lightImpact();
            if (!context.mounted) return;
            context.pop();
          },
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              gapH16,
              _buildProcessingCard(context),
              gapH16,
              if (!_isPremium) ...[_buildRewardAdCard(context), gapH16],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  context.loc.recordingProcessingMessage,
                  textAlign: TextAlign.center,
                  style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurfaceVariant),
                ),
              ),
              gapH24,
            ],
          ),
        ),
      ),
    ),
    floatingActionButton: !_isPremium && _isProcessSucceeded ? _buildFAB(context) : null,
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
  );

  Widget _buildProcessingCard(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.colorScheme.outline.withAlpha(25)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _steps.length,
        separatorBuilder: (context, index) => gapH16,
        itemBuilder: (context, index) {
          final step = _steps[index];
          return _ProcessingStepItem(step: step);
        },
      ),
    ),
  );

  Widget _buildRewardAdCard(BuildContext context) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: context.colorScheme.outline.withAlpha(25)),
    ),
    child: ListView(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        SvgPicture.asset(Assets.giftFillIcon, width: 48, height: 48),
        gapH12,
        Text(
          'Earn a Free Credit While You Wait!',
          textAlign: TextAlign.center,
          style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        gapH12,
        Text(
          'Your audio is being processed. This might take a minute or two depending on its duration. While you wait, would you like to watch a short ad to earn 1 free credit?',
          textAlign: TextAlign.center,
          style: context.textTheme.bodyMedium,
        ),
        gapH12,
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () async {
              await HapticFeedback.lightImpact();
              if (!context.mounted) return;
              await context.read<RewardAdService>().showWhenWaitingTranscribeProcess(context: context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFEA200),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(82)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '🔥 Watch Ad & Earn Credit',
                  style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildFAB(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.lightImpact();
          navigateToSummary();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0767F8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Show Results',
              style: context.textTheme.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProcessingStepItem extends StatelessWidget {
  final _ProcessingStep step;

  const _ProcessingStepItem({required this.step});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (step.progress > 0) _buildStepIcon(context) else const SizedBox(width: 24, height: 24),
      gapW12,
      Expanded(child: Text(step.label, style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
      if (step.state == _ProcessingStepState.loading && step.progress > 0)
        Text(
          '${(step.progress * 100).toInt()}%',
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
    ],
  );

  Widget _buildStepIcon(BuildContext context) {
    switch (step.state) {
      case _ProcessingStepState.completed:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: context.colorScheme.primary, shape: BoxShape.circle),
          child: Icon(Icons.check, color: context.colorScheme.onPrimary, size: 16),
        );
      case _ProcessingStepState.error:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: context.colorScheme.error, shape: BoxShape.circle),
          child: Icon(Icons.close, color: context.colorScheme.onError, size: 16),
        );
      case _ProcessingStepState.loading:
      default:
        return SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            // value: step.progress > 0 ? step.progress : null,
            strokeWidth: 2,
            backgroundColor: context.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(context.colorScheme.primary),
          ),
        );
    }
  }
}
