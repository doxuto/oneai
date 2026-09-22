import 'dart:io';

import 'package:codebase_ai/config/assets.dart';
import 'package:codebase_ai/data/services/admob/banner_ad_widget.dart';
import 'package:codebase_ai/data/services/admob/interstitial_ad_service.dart';
import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/domain/mappers/minute_mapper.dart';
import 'package:codebase_ai/domain/models/meeting_minute_model.dart';
import 'package:codebase_ai/domain/models/transcript_message_model.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/ui/core/localization/localization_extension.dart';
import 'package:codebase_ai/ui/core/themes/dimens.dart';
import 'package:codebase_ai/ui/core/themes/theme_extension.dart';
import 'package:codebase_ai/ui/features/transcription/view_model/transcription_summary_bloc.dart';
import 'package:codebase_ai/ui/features/transcription/widgets/chat_input_widget.dart';
import 'package:codebase_ai/ui/features/transcription/widgets/chat_message_widget.dart';
import 'package:codebase_ai/ui/features/transcription/widgets/feedback_widget.dart';
import 'package:codebase_ai/ui/features/transcription/widgets/minute_section_widget.dart';
import 'package:codebase_ai/ui/features/transcription/widgets/transcript_message_widget.dart';
import 'package:codebase_ai/ui/features/transcription/widgets/transcript_tab_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:just_audio/just_audio.dart';
import 'package:logging/logging.dart';

/// Options for sharing content
enum ShareOption { notesAsPdf, notesAsText, transcriptAsPdf, transcriptAsText, audioFile }

enum AudioPlayerShowingState { playButton, waitForControlDashboard, controlDashboard }

enum AudioPlayerLoadingState { initial, loading, notDownloaded, ready }

/// Screen to display the transcription summary and meeting minutes
class TranscriptionSummaryScreen extends StatefulWidget {
  const TranscriptionSummaryScreen({super.key});

  @override
  State<TranscriptionSummaryScreen> createState() => _TranscriptionSummaryScreenState();
}

class _TranscriptionSummaryScreenState extends State<TranscriptionSummaryScreen> with WidgetsBindingObserver {
  final Logger _logger = Logger('TranscriptionSummaryScreen');
  late String minuteId;
  TranscriptTab _selectedTab = TranscriptTab.minutes;
  final _scrollController = ScrollController();
  final _transcriptScrollController = ScrollController();
  final _chatScrollController = ScrollController();
  MeetingMinute? _meetingMinute;
  Transcript? _transcript;
  final _focusNode = FocusNode();
  bool showFAB = false;
  AudioPlayerShowingState _playerShowingState = AudioPlayerShowingState.playButton;
  AudioPlayerLoadingState _playerLoadingState = AudioPlayerLoadingState.initial;
  AudioPlayer? _audioPlayer;
  Duration _audioDuration = Duration.zero;
  Duration _audioPosition = Duration.zero;
  bool _isPlaying = false;
  int _sliderPosition = -1;

  // Banner Ad instance (shared across tabs)
  // ignore: prefer_const_constructors
  late final InlineAdaptiveBannerAd _bannerAd = InlineAdaptiveBannerAd();

  void _handleTabSelected(TranscriptTab tab) {
    _logger.fine('Tab selected: $tab');
    setState(() {
      _selectedTab = tab;
    });
    if (tab == TranscriptTab.chat) {
      // Dispatch event to initialize chat if empty
      final chatMessages = context.read<TranscriptionSummaryBloc>().state.chatConversation.messages;
      if (chatMessages.isEmpty) {
        context.read<TranscriptionSummaryBloc>().add(const TranscriptionSummaryEvent.initChat());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _handleSendMessage(String message) {
    _logger.fine('Send message: $message');
    context.read<TranscriptionSummaryBloc>().add(TranscriptionSummaryEvent.sendChatMessage(message: message));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void didChangeDependencies() {
    _logger.fine('didChangeDependencies called');
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra is! String) {
      // If no minuteId is provided, navigate back
      context.pop();
      return;
    }
    minuteId = extra;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _logger.fine('dispose called');
    _audioPlayer?.dispose();
    _scrollController.dispose();
    _transcriptScrollController.dispose();
    _chatScrollController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.fine('build called');
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          await _showCongratulationDialog(context);
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: BlocListener<TranscriptionSummaryBloc, TranscriptionSummaryState>(
          listenWhen: (previous, current) => current.minute != null && current.minute != previous.minute,
          listener: (context, state) async {
            // Set up local variables when minute is loaded
            if (state.minute != null) {
              _meetingMinute = minuteToMeetingMinute(state.minute!);
              _transcript = minuteToTranscript(state.minute!);
              setState(() {
                showFAB = state.minute!.gcsUri != null;
                if (state.audioSource != null) {
                  _playerLoadingState = AudioPlayerLoadingState.loading;
                } else {
                  _playerLoadingState = AudioPlayerLoadingState.notDownloaded;
                }
              });
            }
          },
          child: BlocConsumer<TranscriptionSummaryBloc, TranscriptionSummaryState>(
            listenWhen:
                (previous, current) => current.audioSource != null && current.audioSource != previous.audioSource,
            listener: (context, state) async {
              await _initAudioPlayer(audioSource: state.audioSource);
            },
            builder: _buildBody,
          ),
        ),
        floatingActionButton: _selectedTab == TranscriptTab.minutes && showFAB ? _buildFAB(context) : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        resizeToAvoidBottomInset: true,
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) => AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back, color: Color(0xFF2C7DF7)),
      onPressed: () async {
        await HapticFeedback.lightImpact();
        await _showCongratulationDialog(context);
      },
    ),
    title: Text(context.loc.back, style: context.textTheme.titleMedium?.copyWith(color: const Color(0xFF2C7DF7))),
    titleSpacing: 0,
    centerTitle: false,
    actions: [
      PopupMenuButton<ShareOption>(
        onSelected: _handleShareOption,
        tooltip: context.loc.share,
        position: PopupMenuPosition.under,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(context.appTheme.cardRadius)),
        offset: const Offset(0, 8),
        color: Colors.white,
        elevation: 4,
        icon: SvgPicture.asset(
          Assets.shareIcon,
          width: 24,
          height: 24,
          colorFilter: ColorFilter.mode(context.colorScheme.primary, BlendMode.srcIn),
        ),
        itemBuilder:
            (context) => [
              _buildShareMenuItem(context, ShareOption.notesAsPdf, context.loc.shareNotesAsPdf, Assets.pdfIcon),
              _buildDivider(),
              _buildShareMenuItem(context, ShareOption.notesAsText, context.loc.shareNotesAsText, Assets.textIcon),
              _buildDivider(),
              _buildShareMenuItem(
                context,
                ShareOption.transcriptAsPdf,
                context.loc.shareTranscriptAsPdf,
                Assets.pdfIcon,
              ),
              _buildDivider(),
              _buildShareMenuItem(
                context,
                ShareOption.transcriptAsText,
                context.loc.shareTranscriptAsText,
                Assets.noteTextIcon,
              ),
              if (showFAB) ...[
                _buildDivider(),
                _buildShareMenuItem(context, ShareOption.audioFile, context.loc.shareAudioFile, Assets.audioLinesIcon),
              ],
            ],
      ),
    ],
  );

  PopupMenuItem<Never> _buildDivider() => const PopupMenuItem(
    height: 1,
    enabled: false,
    padding: EdgeInsets.zero,
    child: Divider(color: Color(0xFFBDBDBD), height: 1),
  );

  PopupMenuItem<ShareOption> _buildShareMenuItem(
    BuildContext context,
    ShareOption option,
    String text,
    String iconPath,
  ) => PopupMenuItem<ShareOption>(
    value: option,
    height: 44,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text, style: context.textTheme.bodyMedium?.copyWith(color: Colors.black87, fontWeight: FontWeight.w400)),
        SvgPicture.asset(
          iconPath,
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.black87, BlendMode.srcIn),
        ),
      ],
    ),
  );

  void _handleShareOption(ShareOption option) {
    // Implement share functionality based on selected option
    switch (option) {
      case ShareOption.notesAsPdf:
        _shareNotesAsPdf();
        break;
      case ShareOption.notesAsText:
        _shareNotesAsText();
        break;
      case ShareOption.transcriptAsPdf:
        _shareTranscriptAsPdf();
        break;
      case ShareOption.transcriptAsText:
        _shareTranscriptAsText();
        break;
      case ShareOption.audioFile:
        _shareAudioFile();
        break;
    }
  }

  void _shareNotesAsPdf() {
    if (_meetingMinute == null) return;
    context.read<TranscriptionSummaryBloc>().add(
      TranscriptionSummaryEvent.shareNotesAsPdf(
        meetingMinute: _meetingMinute!,
        sharePositionOrigin: sharePositionOrigin(),
      ),
    );
    _showLoadingDialog();
  }

  void _shareNotesAsText() {
    if (_meetingMinute == null) return;
    context.read<TranscriptionSummaryBloc>().add(
      TranscriptionSummaryEvent.shareNotesAsText(
        meetingMinute: _meetingMinute!,
        sharePositionOrigin: sharePositionOrigin(),
      ),
    );
    _showLoadingDialog();
  }

  void _shareTranscriptAsPdf() {
    if (_meetingMinute == null) return;
    context.read<TranscriptionSummaryBloc>().add(
      TranscriptionSummaryEvent.shareTranscriptAsPdf(
        title: _meetingMinute!.title,
        date: _meetingMinute!.date,
        duration: _meetingMinute!.duration,
        transcript: _transcript!,
        sharePositionOrigin: sharePositionOrigin(),
      ),
    );
    _showLoadingDialog();
  }

  void _shareTranscriptAsText() {
    if (_meetingMinute == null) return;
    context.read<TranscriptionSummaryBloc>().add(
      TranscriptionSummaryEvent.shareTranscriptAsText(
        title: _meetingMinute!.title,
        date: _meetingMinute!.date,
        duration: _meetingMinute!.duration,
        transcript: _transcript!,
        sharePositionOrigin: sharePositionOrigin(),
      ),
    );
    _showLoadingDialog();
  }

  Future<void> _shareAudioFile() async {
    final state = context.read<TranscriptionSummaryBloc>().state;
    if (state.isAudioDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.loc.audioIsDownloading)));
      return;
    }

    if (state.audioSource == null) {
      context.read<TranscriptionSummaryBloc>().add(const TranscriptionSummaryEvent.downloadAudio());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.loc.audioIsStartingDownload)));
      return;
    }

    _showLoadingDialog();
    context.read<TranscriptionSummaryBloc>().add(
      TranscriptionSummaryEvent.shareAudioFile(
        audioPath: state.audioSource!.path,
        sharePositionOrigin: sharePositionOrigin(),
      ),
    );
  }

  Rect? sharePositionOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return box != null ? (box.localToGlobal(Offset.zero) & box.size) : null;
  }

  void _showLoadingDialog() {
    // Get bloc outside of the dialog builder to ensure we use the correct instance
    final bloc = context.read<TranscriptionSummaryBloc>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (dialogContext) => BlocProvider<TranscriptionSummaryBloc>.value(
            value: bloc, // Provide the same bloc instance to the dialog context
            child: BlocListener<TranscriptionSummaryBloc, TranscriptionSummaryState>(
              listener: (context, state) async {
                if (!state.isShareLoading && state.errorMessage == null) {
                  await context.read<InterstitialAdService>().showAfterShare(context: context, showLoading: false);
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                } else if (state.errorMessage != null) {
                  Navigator.of(dialogContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.loc.errorSharingContent),
                      backgroundColor: context.colorScheme.error,
                    ),
                  );
                }
              },
              child: Dialog(
                backgroundColor: context.colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      gapH16,
                      Text(context.loc.preparingContent, style: context.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildBody(BuildContext context, TranscriptionSummaryState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(state.errorMessage!), backgroundColor: Colors.red));
      });
    }
    if (state.minute == null || _meetingMinute == null || _transcript == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_meetingMinute!.title, style: context.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          gapH8,
          Text(
            '${_meetingMinute!.date} • ${_meetingMinute!.duration}',
            style: context.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          ),
          gapH16,
          TranscriptTabSelector(selectedTab: _selectedTab, onTabSelected: _handleTabSelected),
          gapH16,
          Expanded(child: _buildTabContent(context)),
        ],
      ),
    );
  }

  Widget _buildTabContent(BuildContext context) {
    switch (_selectedTab) {
      case TranscriptTab.minutes:
        return _buildMinutesTab(context);
      case TranscriptTab.transcript:
        return _buildTranscriptTab(context);
      case TranscriptTab.chat:
        return _buildChatTab(context);
    }
  }

  Widget _buildMinutesTab(BuildContext context) => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(bottom: 16), child: _bannerAd),
              ...?_meetingMinute?.sections.map((section) => MinuteSectionWidget(section: section)),
              const SafeArea(minimum: EdgeInsets.only(bottom: 16), child: FeedbackWidget()),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buildTranscriptTab(BuildContext context) => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          controller: _transcriptScrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(bottom: 16), child: _bannerAd),
              ...?_transcript?.messages.map((message) => TranscriptMessageWidget(message: message)),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _buildChatTab(BuildContext context) {
    final state = context.watch<TranscriptionSummaryBloc>().state;
    final chatMessages = state.chatConversation.messages;
    final isChatLoading = state.isChatLoading;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _chatScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(bottom: 16), child: _bannerAd),
                ...chatMessages.map((message) => ChatMessageWidget(message: message)),
                if (isChatLoading) const ChatTypingIndicator(),
              ],
            ),
          ),
        ),
        gapH16,
        SafeArea(
          minimum: const EdgeInsets.only(bottom: 16),
          child: ChatInputWidget(
            onMessageSent: _handleSendMessage,
            focusNode: _focusNode,
            suggestedQuestions: state.suggestedQuestions,
          ),
        ),
      ],
    );
  }

  Future<void> _initAudioPlayer({File? audioSource}) async {
    _logger.fine('Initializing audio player');

    if (audioSource == null) {
      // Reset to default state
      setState(() {
        _audioPlayer = null;
        _audioDuration = Duration.zero;
        _audioPosition = Duration.zero;
        _playerLoadingState = AudioPlayerLoadingState.initial;
        _playerShowingState = AudioPlayerShowingState.playButton;
        _isPlaying = false;
        _sliderPosition = -1;
      });
      return;
    }

    _audioPlayer = AudioPlayer();

    setState(() {
      _playerLoadingState = AudioPlayerLoadingState.loading;
    });

    _audioPlayer?.positionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _audioPosition = pos;
          _logger.fine('Audio position: $_audioPosition');
        });
      }
    });
    _audioPlayer?.playerStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          _logger.fine('Audio player state: $state');

          if (state.processingState == ProcessingState.ready) {
            // Player is ready to play, only set once to avoid state changes on seek to new position
            _logger.fine('Audio player is ready, _playerShowingState = $_playerShowingState');
            _playerLoadingState = AudioPlayerLoadingState.ready;
            if (_playerShowingState == AudioPlayerShowingState.waitForControlDashboard) {
              _playerShowingState = AudioPlayerShowingState.controlDashboard;
              _logger.fine('Audio player is ready, go to control dashboard');
            }
          }
        });
      }
    });

    await _audioPlayer?.setFilePath(audioSource.path);

    setState(() {
      _audioDuration = _audioPlayer?.duration ?? Duration.zero;
      _audioPosition = Duration.zero;
      _isPlaying = false;
    });
  }

  Future<void> _onPlayPressed() async {
    final state = context.read<TranscriptionSummaryBloc>().state;

    if (state.isAudioDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.loc.audioIsDownloading)));
      setState(() {
        _playerShowingState = AudioPlayerShowingState.waitForControlDashboard;
        _logger.fine('Audio player is downloading, _playerShowingState = $_playerShowingState');
      });
      return;
    }

    if (state.audioSource == null) {
      context.read<TranscriptionSummaryBloc>().add(const TranscriptionSummaryEvent.downloadAudio());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.loc.audioIsStartingDownload)));
      setState(() {
        _playerShowingState = AudioPlayerShowingState.waitForControlDashboard;
        _logger.fine('Audio player is starting download, _playerShowingState = $_playerShowingState');
      });
      return;
    }

    if (_playerLoadingState != AudioPlayerLoadingState.ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.loc.audioIsNotReady), backgroundColor: Theme.of(context).colorScheme.error),
      );
      setState(() {
        _playerShowingState = AudioPlayerShowingState.waitForControlDashboard;
        _logger.fine('Audio player is not ready, _playerShowingState = $_playerShowingState');
      });
      return;
    }

    _logger.fine('Play pressed, isPlaying: $_isPlaying');
    await HapticFeedback.lightImpact();
    setState(() {
      _playerShowingState = AudioPlayerShowingState.controlDashboard;
    });
  }

  Widget _buildFAB(BuildContext context) {
    if (_playerShowingState != AudioPlayerShowingState.controlDashboard ||
        _playerLoadingState != AudioPlayerLoadingState.ready) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 100),
        child: SizedBox(
          width: 42,
          height: 42,
          child: BlocSelector<TranscriptionSummaryBloc, TranscriptionSummaryState, bool>(
            selector: (state) => state.isAudioDownloading,
            builder:
                (context, isAudioDownloading) =>
                    BlocSelector<TranscriptionSummaryBloc, TranscriptionSummaryState, bool>(
                      selector: (state) => state.audioSource != null,
                      builder:
                          (context, hasAudio) => FloatingActionButton(
                            onPressed: _onPlayPressed,
                            backgroundColor: const Color(0xFF2C7DF7),
                            elevation: 2,
                            shape: const CircleBorder(),
                            mini: true,
                            child:
                                _playerLoadingState == AudioPlayerLoadingState.initial ||
                                        (hasAudio && _playerLoadingState == AudioPlayerLoadingState.loading) ||
                                        isAudioDownloading
                                    ? const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          strokeWidth: 2.2,
                                        ),
                                      ),
                                    )
                                    : SvgPicture.asset(
                                      Assets.playIcon,
                                      width: 24,
                                      height: 24,
                                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                    ),
                          ),
                    ),
          ),
        ),
      );
    }

    return _buildAudioPlayerUI();
  }

  Widget _buildAudioPlayerUI() {
    // Supported speeds
    final List<double> speeds = [0.5, 1.0, 1.5, 2.0];
    final currentSpeed = _audioPlayer?.speed ?? 1.0;
    final sliderPosition = _sliderPosition == -1 ? _audioPosition.inMilliseconds : _sliderPosition;

    void _changeSpeed() {
      _logger.fine('Change speed pressed. Current speed: ${_audioPlayer?.speed}');
      final currentIndex = speeds.indexOf(currentSpeed);
      final nextIndex = (currentIndex + 1) % speeds.length;
      final newSpeed = speeds[nextIndex];
      _audioPlayer?.setSpeed(newSpeed);
      setState(() {});
    }

    void _seekRelative(Duration offset) {
      _logger.fine('Seek relative: $offset');
      final newPosition = _audioPosition + offset;
      _audioPlayer?.seek(newPosition < Duration.zero ? Duration.zero : newPosition);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 100, left: 32),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Speed button
                TextButton(
                  onPressed: () async {
                    await HapticFeedback.lightImpact();
                    _changeSpeed();
                  },
                  child: Text(
                    '${(_audioPlayer?.speed ?? 1.0).toStringAsFixed(1)}x',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2C7DF7)),
                  ),
                ),
                // Backward 10s
                IconButton(
                  icon: const Icon(Icons.replay_10, color: Color(0xFF2C7DF7)),
                  onPressed: () async {
                    await HapticFeedback.lightImpact();
                    _seekRelative(const Duration(seconds: -10));
                  },
                ),
                // Play/Pause
                IconButton(
                  icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: const Color(0xFF2C7DF7), size: 32),
                  onPressed: () async {
                    await HapticFeedback.lightImpact();
                    if (_isPlaying) {
                      await _audioPlayer?.pause();
                    } else {
                      await _audioPlayer?.play();
                    }
                  },
                ),
                // Forward 10s
                IconButton(
                  icon: const Icon(Icons.forward_10, color: Color(0xFF2C7DF7)),
                  onPressed: () async {
                    await HapticFeedback.lightImpact();
                    _seekRelative(const Duration(seconds: 10));
                  },
                ),
                // Download (optional, as in image)
                // IconButton(
                //   icon: const Icon(Icons.download_rounded, color: Color(0xFF2C7DF7)),
                //   onPressed: () {
                //    HapticFeedback.lightImpact();
                //     // Implement download logic if needed
                //   },
                // ),
                // Close
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF2C7DF7)),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _audioPlayer?.pause();
                    setState(() {
                      _playerShowingState = AudioPlayerShowingState.playButton;
                    });
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    _formatDuration(millisecondToDuration(sliderPosition)),
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  Expanded(
                    child: Slider(
                      value:
                          (sliderPosition < 0)
                              ? 0.0
                              : (sliderPosition <= _audioDuration.inMilliseconds)
                              ? sliderPosition.toDouble()
                              : _audioDuration.inMilliseconds.toDouble(),
                      min: 0,
                      max: _audioDuration.inMilliseconds.toDouble(),
                      onChangeStart: (value) {
                        setState(() {
                          _sliderPosition = _audioPosition.inMilliseconds;
                          _logger.fine('Slider start: $_sliderPosition');
                        });
                      },
                      onChanged: (value) {
                        setState(() {
                          _sliderPosition = value.toInt();
                          _logger.fine('Slider change: $_sliderPosition');
                        });
                      },
                      onChangeEnd: (value) {
                        setState(() {
                          _sliderPosition = -1;
                          _logger.fine('Slider end: $_sliderPosition, last value: $value');
                        });
                        _audioPlayer?.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Text(_formatDuration(_audioDuration), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Duration millisecondToDuration(int durationMs) => Duration(milliseconds: durationMs);

  Future<void> _showCongratulationDialog(BuildContext context) async {
    if (!context.mounted) {
      return;
    }

    final pref = context.read<SharedPreferencesService>();
    final minuteCount = context.read<MinuteUseCase>().minutes.length;

    if (!(await pref.getShowCongratulationDialog() && minuteCount == 1)) {
      _logger.fine('Congratulation dialog not shown, minuteCount: $minuteCount');
      // Show interstitial ad if available
      if (!context.mounted) return;
      await context.read<InterstitialAdService>().showBeforeSummaryExit(context: context);
      if (!context.mounted) return;
      context.pop();
      return;
    }

    if (!context.mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text('Congratulation', style: context.textTheme.titleLarge)],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Congratulations on transcribing your first audio! We hope you're enjoying the app so far. If you have a moment, could you rate your experience? Your feedback helps us improve and serve you better!",
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
                        onPressed: () async {
                          await HapticFeedback.lightImpact();
                          // Rating logic
                          final inAppReview = InAppReview.instance;
                          if (await inAppReview.isAvailable()) {
                            await inAppReview.requestReview();
                          } else {
                            await inAppReview.openStoreListing();
                          }
                          // Close the dialog and the screen
                          await context.read<SharedPreferencesService>().markShowCongratulationDialog();
                          Navigator.of(ctx).pop();
                          Navigator.of(ctx).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          "Sure, I'll rate it",
                          style: context.textTheme.labelLarge?.copyWith(color: Colors.blue),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFBDBDBD)),
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          await HapticFeedback.lightImpact();
                          await context.read<SharedPreferencesService>().markShowCongratulationDialog();
                          Navigator.of(ctx).pop();
                          Navigator.of(ctx).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
                          ),
                        ),
                        child: Text(
                          'Not now',
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
}
