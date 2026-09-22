import 'dart:io';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:codebase_ai/data/repositories/oneai_repository.dart';
import 'package:codebase_ai/data/repositories/share_repository.dart';
import 'package:codebase_ai/domain/models/chat_message_model.dart';
import 'package:codebase_ai/domain/models/meeting_minute_model.dart';
import 'package:codebase_ai/domain/models/minute_model.dart';
import 'package:codebase_ai/domain/models/transcript_message_model.dart';
import 'package:codebase_ai/domain/use_cases/minute_usecase.dart';
import 'package:codebase_ai/utils/result.dart' as result;
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';

part 'transcription_summary_bloc.freezed.dart';

/// Events for the TranscriptionSummary bloc
@freezed
sealed class TranscriptionSummaryEvent with _$TranscriptionSummaryEvent {
  /// Load minute by id
  const factory TranscriptionSummaryEvent.loadMinute({required String minuteId}) = _LoadMinute;

  /// Share meeting minutes as PDF
  const factory TranscriptionSummaryEvent.shareNotesAsPdf({
    required MeetingMinute meetingMinute,
    Rect? sharePositionOrigin,
  }) = _ShareNotesAsPdf;

  /// Share meeting minutes as text
  const factory TranscriptionSummaryEvent.shareNotesAsText({
    required MeetingMinute meetingMinute,
    Rect? sharePositionOrigin,
  }) = _ShareNotesAsText;

  /// Share transcript as PDF
  const factory TranscriptionSummaryEvent.shareTranscriptAsPdf({
    required String title,
    required String date,
    required String duration,
    required Transcript transcript,
    Rect? sharePositionOrigin,
  }) = _ShareTranscriptAsPdf;

  /// Share transcript as text
  const factory TranscriptionSummaryEvent.shareTranscriptAsText({
    required String title,
    required String date,
    required String duration,
    required Transcript transcript,
    Rect? sharePositionOrigin,
  }) = _ShareTranscriptAsText;

  /// Share audio file
  const factory TranscriptionSummaryEvent.shareAudioFile({required String audioPath, Rect? sharePositionOrigin}) =
      _ShareAudioFile;

  /// Chat: send a message
  const factory TranscriptionSummaryEvent.sendChatMessage({required String message}) = _SendChatMessage;

  /// Chat: initialize or reset chat
  const factory TranscriptionSummaryEvent.initChat() = _InitChat;

  const factory TranscriptionSummaryEvent.downloadAudio() = _DownloadAudio;

  const factory TranscriptionSummaryEvent.updateSpeakers({required String speakerId, required String newName}) =
      _UpdateSpeakers;
}

/// States for the TranscriptionSummary bloc
@freezed
sealed class TranscriptionSummaryState with _$TranscriptionSummaryState {
  const factory TranscriptionSummaryState({
    @Default(false) bool isLoading,
    String? errorMessage,
    Minute? minute,
    @Default(false) bool isShareLoading,
    @Default(false) bool isChatLoading,
    @Default(ChatConversation(messages: [])) ChatConversation chatConversation,
    @Default([]) List<String> suggestedQuestions,
    @Default(false) bool isAudioDownloading,
    @Default(null) File? audioSource,
    @Default({}) Set<String> speakerIdsLoading,
  }) = _TranscriptionSummaryState;
}

/// TranscriptionSummaryBloc manages the sharing functionality for the TranscriptionSummaryScreen
class TranscriptionSummaryBloc extends Bloc<TranscriptionSummaryEvent, TranscriptionSummaryState> {
  final ShareRepository _shareRepository;
  final MinuteUseCase _minuteUseCase;
  final OneAiRepository _oneAiRepository;
  final _log = Logger('TranscriptionSummaryBloc');

  /// Constructor
  TranscriptionSummaryBloc({
    required ShareRepository shareRepository,
    required MinuteUseCase minuteUseCase,
    required OneAiRepository oneAiRepository,
  }) : _shareRepository = shareRepository,
       _minuteUseCase = minuteUseCase,
       _oneAiRepository = oneAiRepository,
       super(const TranscriptionSummaryState()) {
    on<_LoadMinute>(_onLoadMinute);
    on<_ShareNotesAsPdf>(_onShareNotesAsPdf);
    on<_ShareNotesAsText>(_onShareNotesAsText);
    on<_ShareTranscriptAsPdf>(_onShareTranscriptAsPdf);
    on<_ShareTranscriptAsText>(_onShareTranscriptAsText);
    on<_ShareAudioFile>(_onShareAudioFile);
    on<_SendChatMessage>(_onSendChatMessage);
    on<_InitChat>(_onInitChat);
    on<_DownloadAudio>(_onDownloadAudio);
    on<_UpdateSpeakers>(_onUpdateSpeakers);
  }

  Future<void> _onLoadMinute(_LoadMinute event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));
    final res = await _minuteUseCase.getMinuteById(event.minuteId);
    switch (res) {
      case result.Ok(value: final minute):
        File? audioSource;
        if (minute.gcsUri != null) {
          // Check if file existed, init for audio source
          final filePath = await getAudioLocalFilePath(minute.gcsUri, minute.title);
          _log.fine('_onLoadMinute Audio file path: $filePath');
          if (filePath != null) {
            final file = File(filePath);
            if (await file.exists()) {
              _log.fine('Audio file already exists at: $filePath');
              audioSource = file;
            }
          }
        }
        emit(state.copyWith(isLoading: false, minute: minute, errorMessage: null, audioSource: audioSource));

        // If speakers are not loaded, fetch them
        if (minute.speakers == null) {
          final speakersResult = await _oneAiRepository.getSpeakers(minuteId: event.minuteId);
          switch (speakersResult) {
            case result.Ok(value: final speakers):
              _log.fine('Speakers loaded: $speakers');
              emit(state.copyWith(minute: minute.copyWith(speakers: speakers)));
            case result.Error(error: final err):
              _log.severe('Error fetching speakers: $err');
          }
        }
      case result.Error(error: final err):
        emit(state.copyWith(isLoading: false, errorMessage: err.toString()));
    }
  }

  Future<void> _onShareNotesAsPdf(_ShareNotesAsPdf event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(isShareLoading: true, errorMessage: null));
    final res = await _shareRepository.shareNotesAsPdf(
      event.meetingMinute,
      sharePositionOrigin: event.sharePositionOrigin,
    );
    switch (res) {
      case result.Ok():
        emit(state.copyWith(isShareLoading: false, errorMessage: null));
      case result.Error(error: final err):
        _log.severe('Error sharing notes as PDF: $err');
        emit(state.copyWith(isShareLoading: false, errorMessage: err.toString()));
    }
  }

  Future<void> _onShareNotesAsText(_ShareNotesAsText event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(isShareLoading: true, errorMessage: null));
    final res = await _shareRepository.shareNotesAsText(
      event.meetingMinute,
      sharePositionOrigin: event.sharePositionOrigin,
    );
    switch (res) {
      case result.Ok():
        emit(state.copyWith(isShareLoading: false, errorMessage: null));
      case result.Error(error: final err):
        _log.severe('Error sharing notes as text: $err');
        emit(state.copyWith(isShareLoading: false, errorMessage: err.toString()));
    }
  }

  Future<void> _onShareTranscriptAsPdf(_ShareTranscriptAsPdf event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(isShareLoading: true, errorMessage: null));
    final res = await _shareRepository.shareTranscriptAsPdf(
      event.title,
      event.date,
      event.duration,
      event.transcript,
      sharePositionOrigin: event.sharePositionOrigin,
    );
    switch (res) {
      case result.Ok():
        emit(state.copyWith(isShareLoading: false, errorMessage: null));
      case result.Error(error: final err):
        _log.severe('Error sharing transcript as PDF: $err');
        emit(state.copyWith(isShareLoading: false, errorMessage: err.toString()));
    }
  }

  Future<void> _onShareTranscriptAsText(_ShareTranscriptAsText event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(isShareLoading: true, errorMessage: null));
    final res = await _shareRepository.shareTranscriptAsText(
      event.title,
      event.date,
      event.duration,
      event.transcript,
      sharePositionOrigin: event.sharePositionOrigin,
    );
    switch (res) {
      case result.Ok():
        emit(state.copyWith(isShareLoading: false, errorMessage: null));
      case result.Error(error: final err):
        _log.severe('Error sharing transcript as text: $err');
        emit(state.copyWith(isShareLoading: false, errorMessage: err.toString()));
    }
  }

  Future<void> _onShareAudioFile(_ShareAudioFile event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(isShareLoading: true, errorMessage: null));
    final res = await _shareRepository.shareAudioFile(event.audioPath, sharePositionOrigin: event.sharePositionOrigin);
    switch (res) {
      case result.Ok():
        emit(state.copyWith(isShareLoading: false, errorMessage: null));
      case result.Error(error: final err):
        _log.severe('Error sharing audio file: $err');
        emit(state.copyWith(isShareLoading: false, errorMessage: err.toString()));
    }
  }

  Future<void> _onSendChatMessage(_SendChatMessage event, Emitter<TranscriptionSummaryState> emit) async {
    final updatedMessages = [
      ...state.chatConversation.messages,
      ChatMessage(message: event.message, senderType: MessageSenderType.user, timestamp: DateTime.now()),
    ];
    emit(
      state.copyWith(
        isChatLoading: true,
        errorMessage: null,
        chatConversation: ChatConversation(messages: updatedMessages),
      ),
    );
    final res = await _oneAiRepository.postChat(
      minuteId: state.minute!.id,
      question: event.message,
      summaryText: state.minute!.summary?.summaryText,
    );
    switch (res) {
      case result.Ok(value: final response):
        emit(
          state.copyWith(
            isChatLoading: false,
            errorMessage: null,
            chatConversation: ChatConversation(
              messages: [
                ...updatedMessages,
                ChatMessage(message: response.answer, senderType: MessageSenderType.bot, timestamp: DateTime.now()),
              ],
            ),
          ),
        );
      case result.Error(error: final err):
        _log.severe('Error sending chat message: $err');
        emit(state.copyWith(isChatLoading: false, errorMessage: err.toString()));
    }
  }

  Future<void> _onInitChat(_InitChat event, Emitter<TranscriptionSummaryState> emit) async {
    emit(
      state.copyWith(
        chatConversation: ChatConversation(
          messages: [
            ChatMessage(
              message: "I'm here to help you with your note. What would you like to know?",
              senderType: MessageSenderType.bot,
              timestamp: DateTime.now(),
            ),
          ],
        ),
      ),
    );

    final res = await _oneAiRepository.postShortQuestions(
      minuteId: state.minute!.id,
      languageCode: state.minute!.summaryLanguage ?? 'en_US',
      // languageCode: 'en_US',
    );
    switch (res) {
      case result.Ok(value: final response):
        emit(state.copyWith(suggestedQuestions: response.shortQuestions));
      case result.Error(error: final err):
        _log.severe('Error sending chat message: $err');
      // emit(state.copyWith(errorMessage: err.toString()));
    }
  }

  Future<void> _onDownloadAudio(_DownloadAudio event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(isAudioDownloading: true, errorMessage: null));
    final res = await _getAudioSource(state.minute?.gcsUri);
    emit(state.copyWith(isAudioDownloading: false, audioSource: res));
  }

  Future<File?> _getAudioSource(String? audioUri) async {
    if (audioUri == null) {
      return null;
    }
    final filePath = await getAudioLocalFilePath(audioUri, state.minute?.title);
    if (filePath == null) {
      return null;
    }
    final file = File(filePath);

    // Check if file exists
    if (await file.exists()) {
      _log.fine('Audio file already exists at: $filePath');
      return file;
    }

    // Download the file using Dio
    try {
      final dio = Dio();
      final downloadUrl = await FirebaseStorage.instance.refFromURL(audioUri).getDownloadURL();
      await dio.download(downloadUrl, filePath);
      _log.fine('Audio file downloaded to: $filePath');
      return file;
    } catch (e, stack) {
      _log.severe('Failed to download audio: $e', e, stack);
      return null;
    }
  }

  Future<String?> getAudioLocalFilePath(String? audioUri, String? title) async {
    try {
      if (audioUri == null) {
        return null;
      }

      final downloadUrl = await FirebaseStorage.instance.refFromURL(audioUri).getDownloadURL();
      _log.fine('Audio download URL: $downloadUrl');

      // Extract file name from downloadUrl
      final uri = Uri.parse(downloadUrl);
      final fileNameFromUrl = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : 'audio-${audioUri.hashCode}';

      // Generate a unique file name from the downloadUrl using SHA256 hash
      final fileName = title == null ? fileNameFromUrl : '${title.toLowerCase().replaceAll(' ', '-')}.mp3';

      // Get the temporary directory
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/audio/$fileName';
      _log.fine('Audio file path: $filePath');
      return filePath;
    } catch (e, stack) {
      _log.severe('Failed to get audio local file path: $e', e, stack);
      return null;
    }
  }

  Future<void> _onUpdateSpeakers(_UpdateSpeakers event, Emitter<TranscriptionSummaryState> emit) async {
    emit(state.copyWith(speakerIdsLoading: {...state.speakerIdsLoading, event.speakerId}, errorMessage: null));
    final res = await _minuteUseCase.updateSpeakers(
      minuteId: state.minute!.id,
      speakerId: event.speakerId,
      newName: event.newName,
    );
    switch (res) {
      case result.Ok():
        emit(
          state.copyWith(
            speakerIdsLoading: Set<String>.from(state.speakerIdsLoading)..remove(event.speakerId),
            minute: state.minute?.copyWith(speakers: {...?state.minute?.speakers, event.speakerId: event.newName}),
            errorMessage: null,
          ),
        );
      case result.Error(error: final err):
        _log.severe('Error updating speaker name: $err');
        emit(
          state.copyWith(
            speakerIdsLoading: Set<String>.from(state.speakerIdsLoading)..remove(event.speakerId),
            errorMessage: 'Failed to update speaker name',
          ),
        );
    }
  }
}
