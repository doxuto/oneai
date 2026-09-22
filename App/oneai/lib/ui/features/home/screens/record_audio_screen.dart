import 'dart:async';

import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/routing/routes.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/core/widgets/language_selector.dart';
import 'package:codebase_ai/ui/core/widgets/premium_status_builder.dart';
import 'package:codebase_ai/ui/features/home/widgets/prompt_language_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Represents the different states of the audio recording
enum RecordingState {
  /// Initial state, before recording has started
  initial,

  /// Recording in progress
  recording,

  /// Recording is paused
  paused,
}

/// Screen that allows recording audio for meeting minutes
class RecordAudioScreen extends StatefulWidget {
  /// Creates a new instance of [RecordAudioScreen]
  const RecordAudioScreen({super.key});

  @override
  State<RecordAudioScreen> createState() => _RecordAudioScreenState();
}

class _RecordAudioScreenState extends State<RecordAudioScreen> with TickerProviderStateMixin {
  RecordingState _recordingState = RecordingState.initial;
  late Timer _timer;
  int _recordingSeconds = 0;
  late AnimationController _waveAnimationController;
  final List<double> _waveOpacities = [1.0, 0.8, 0.6, 0.4];
  late final AudioRecorder _audioRecorder;
  String? _audioPath;

  final SharedPreferencesService _preferencesService = SharedPreferencesService();
  Language? _audioLanguage;
  Language? _summaryLanguage;
  String? _recordingContext;
  String? _keywords;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _waveAnimationController = AnimationController(duration: const Duration(milliseconds: 3000), vsync: this);
    _waveAnimationController.repeat();
    _recordingState = RecordingState.initial;
    _timer = Timer(Duration.zero, () {});
    _loadLanguagesFromPreferences();
  }

  Future<void> _loadLanguagesFromPreferences() async {
    final audioResult = await _preferencesService.getAudioLanguage();
    final summaryResult = await _preferencesService.getSummaryLanguage();
    setState(() {
      if (audioResult != null) {
        _audioLanguage = Language.values.byName(audioResult);
      }
      if (summaryResult != null) {
        _summaryLanguage = Language.values.byName(summaryResult);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _waveAnimationController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (await _audioRecorder.hasPermission()) {
      final tempDir = await getApplicationDocumentsDirectory();
      final filePath = '${tempDir.path}/minutes_ai_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100),
        path: filePath,
      );
      setState(() {
        _audioPath = filePath;
        _recordingState = RecordingState.recording;
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordingSeconds++;
            });
          }
        });
      });
    }
  }

  Future<void> _pauseRecording() async {
    await _audioRecorder.pause();
    setState(() {
      _recordingState = RecordingState.paused;
      _timer.cancel();
    });
  }

  Future<void> _resumeRecording() async {
    await _audioRecorder.resume();
    setState(() {
      _recordingState = RecordingState.recording;
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingSeconds++;
          });
        }
      });
    });
  }

  Future<void> _stopAndClearRecording() async {
    await _audioRecorder.cancel();
    setState(() {
      _audioPath = null;
      _recordingState = RecordingState.initial;
      _recordingSeconds = 0;
      _timer.cancel();
    });
  }

  Future<void> _toggleRecording() async {
    switch (_recordingState) {
      case RecordingState.initial:
        await _startRecording();
        break;
      case RecordingState.recording:
        await _pauseRecording();
        break;
      case RecordingState.paused:
        await _resumeRecording();
        break;
    }
  }

  String _formatDuration() {
    final minutes = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _getRecordingStatusText() {
    switch (_recordingState) {
      case RecordingState.initial:
        return context.loc.tapToStartRecording;
      case RecordingState.recording:
        return context.loc.tapToStopRecording;
      case RecordingState.paused:
        return context.loc.recordingPaused;
    }
  }

  Widget _getRecordingIcon() {
    switch (_recordingState) {
      case RecordingState.initial:
        return SvgPicture.asset(
          Assets.microphoneFilledIcon,
          width: 36,
          height: 36,
          colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn),
        );
      case RecordingState.recording:
        return SvgPicture.asset(
          Assets.microphoneFilledIcon,
          width: 36,
          height: 36,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
      case RecordingState.paused:
        return SvgPicture.asset(
          Assets.microphoneFilledIcon,
          width: 36,
          height: 36,
          colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn),
        );
    }
  }

  Future<void> _showExitWarningDialog(BuildContext context) async => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder:
        (BuildContext context) => AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                Assets.warningTriangleIcon,
                width: 18,
                height: 18,
                colorFilter: const ColorFilter.mode(Color(0xFFF8C307), BlendMode.srcIn),
              ),
              gapW8,
              Text(context.loc.warning, style: context.textTheme.titleLarge),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.loc.exitRecordingWarning, textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
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
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
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
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        await _stopAndClearRecording();
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                        ),
                      ),
                      child: Text(
                        context.loc.exit,
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

  Widget _buildTranscribeButton(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: Visibility(
      visible: _recordingState == RecordingState.paused,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: PremiumStatusBuilder(
        builder:
            (BuildContext context, PremiumStatus status) => ElevatedButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                premiumActionWrapper(context, status, () async {
                  if (_audioPath != null) {
                    await _audioRecorder.stop();
                    await context.push(
                      Routes.audioProcessing,
                      extra: {
                        'audioPath': _audioPath,
                        'audioLanguage': _audioLanguage?.name,
                        'summaryLanguage': _summaryLanguage?.name,
                        'recordingContext': _recordingContext,
                        'keywords': _keywords,
                      },
                    );
                  }
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colorScheme.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: Text(
                status != PremiumStatus.nonPremiumNoCredits
                    ? context.loc.transcribeAndSummarize
                    : 'Watch Ad to Transcribe',
              ),
            ),
      ),
    ),
  );

  Future<void> _openPromptLanguageSheet() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      // return a map of values
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => PromptLanguageSheet(
            initialAudioLanguage: _audioLanguage,
            initialSummaryLanguage: _summaryLanguage,
            initialRecordingContext: _recordingContext,
            initialKeywords: _keywords,
          ),
    );
    if (result != null) {
      setState(() {
        _audioLanguage = result['audioLanguage'] as Language?;
        _summaryLanguage = result['summaryLanguage'] as Language?;
        _recordingContext = result['recordingContext'] as String?;
        _keywords = result['keywords'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _recordingState == RecordingState.initial,
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop) {
        await _showExitWarningDialog(context);
      }
    },
    child: Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await HapticFeedback.lightImpact();
            if (_recordingState == RecordingState.initial) {
              Navigator.of(context).pop();
            } else {
              await _showExitWarningDialog(context);
            }
          },
        ),
        title: Row(
          children: [
            SvgPicture.asset(Assets.circularComplicationIcon, width: 32, height: 32),
            gapW8,
            Text('One AI', style: context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: false,
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
                  // Recording button with wave animation
                  Center(
                    child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Keep wave containers for all states, just hide them when not recording
                          ...List.generate(
                            4,
                            (index) => AnimatedBuilder(
                              animation: _waveAnimationController,
                              builder: (context, child) {
                                final delay = index * 0.2;
                                final value = (_waveAnimationController.value + delay) % 1.0;
                                final size = 120.0 + (value * 100.0);
                                final opacity =
                                    _recordingState == RecordingState.recording
                                        ? (1.0 - value) * _waveOpacities[index]
                                        : 0.0;

                                return Opacity(
                                  opacity: opacity,
                                  child: Container(
                                    width: size,
                                    height: size,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: context.colorScheme.primary.withAlpha(128), width: 1.5),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Main recording button
                          GestureDetector(
                            onTap: () async {
                              await HapticFeedback.lightImpact();
                              await _toggleRecording();
                            },
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    _recordingState == RecordingState.recording
                                        ? context.colorScheme.primary
                                        : Colors.white,
                                border: Border.all(
                                  color: context.colorScheme.primary,
                                  width: _recordingState == RecordingState.paused ? 2 : 1,
                                ),
                              ),
                              child: Center(child: _getRecordingIcon()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  gapH24,
                  // Recording status text
                  Text(
                    _getRecordingStatusText(),
                    style: context.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
                  ),
                  // Recording timer
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Opacity(
                      opacity: _recordingState == RecordingState.initial ? 0.0 : 1.0,
                      child: Text(
                        _recordingState == RecordingState.initial ? '00:00' : _formatDuration(),
                        style: context.textTheme.bodyMedium?.copyWith(
                          color:
                              _recordingState == RecordingState.recording
                                  ? context.colorScheme.primary
                                  : Colors.grey[500],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 60),
                  // Prompt & Language button
                  SizedBox(
                    height: 48,
                    child: TextButton.icon(
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        await _openPromptLanguageSheet();
                      },
                      iconAlignment: IconAlignment.end,
                      icon: SvgPicture.asset(
                        Assets.settingsIcon,
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn),
                      ),
                      label: Text(context.loc.promptAndLanguage),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(child: _buildTranscribeButton(context)),
          ],
        ),
      ),
    ),
  );
}
