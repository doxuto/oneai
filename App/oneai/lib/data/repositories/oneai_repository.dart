import 'package:codebase_ai/data/services/api/oneai/oneai_api_service.dart';
import 'package:codebase_ai/data/services/model/oneai/minute_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/summary_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/transcription_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/user_dto.dart';
import 'package:codebase_ai/domain/models/chat_model.dart';
import 'package:codebase_ai/domain/models/minute_model.dart';
import 'package:codebase_ai/domain/models/oneai_user_model.dart';
import 'package:codebase_ai/domain/models/question_model.dart';
import 'package:codebase_ai/domain/models/summary_model.dart';
import 'package:codebase_ai/domain/models/tag_model.dart';
import 'package:codebase_ai/domain/models/transcription_model.dart';
import 'package:codebase_ai/utils/result.dart';

class OneAiRepository {
  final OneAiApiService _apiService;

  OneAiRepository(this._apiService);

  // Tags Management
  Future<Result<Tag>> createTag(String name) async {
    final result = await _apiService.createTag(name);
    return switch (result) {
      Ok(value: final dto) => Result.ok(Tag(id: dto.id, name: dto.name)),
      Error(error: final error) => Result.error(error),
    };
  }

  Future<Result<Tag>> updateTag(String tagId, String name) async {
    final result = await _apiService.updateTag(tagId, name);
    return switch (result) {
      Ok(value: final dto) => Result.ok(Tag(id: dto.id, name: dto.name)),
      Error(error: final error) => Result.error(error),
    };
  }

  Future<Result<void>> deleteTag(String tagId) => _apiService.deleteTag(tagId);

  Future<Result<List<Tag>>> getAllTags() async {
    final result = await _apiService.getAllTags();
    return switch (result) {
      Ok(value: final dtos) => Result.ok(dtos.map((dto) => Tag(id: dto.id, name: dto.name)).toList()),
      Error(error: final error) => Result.error(error),
    };
  }

  // Minutes Management
  Future<Result<Minute>> getMinuteById(String minuteId) async {
    final result = await _apiService.getMinuteById(minuteId);
    return switch (result) {
      Ok(value: final dto) => Result.ok(_mapMinuteDtoToModel(dto)),
      Error(error: final error) => Result.error(error),
    };
  }

  Future<Result<MinuteResponse>> getMinutes({String? startAfterDocId, int limit = 10}) async {
    final result = await _apiService.getMinutes(startAfterDocId: startAfterDocId, limit: limit);
    return switch (result) {
      Ok(value: final dto) => Result.ok(_mapMinuteResponseDtoToModel(dto)),
      Error(error: final error) => Result.error(error),
    };
  }

  Future<Result<void>> updateMinuteById(String minuteId, {String? title, String? iconAsset, List<String>? tags}) =>
      _apiService.updateMinuteById(minuteId, title: title, iconAsset: iconAsset, tags: tags);

  Future<Result<void>> deleteMinuteById(String minuteId) => _apiService.deleteMinuteById(minuteId);

  // Transcription
  Future<Result<Transcription>> transcribe({
    required String filePath,
    String? audioLanguage,
    String? summaryLanguage,
    String? keywords,
    String? description,
  }) async {
    final result = await _apiService.transcribe(
      filePath: filePath,
      audioLanguage: audioLanguage,
      summaryLanguage: summaryLanguage,
      keywords: keywords,
      description: description,
    );
    switch (result) {
      case Ok(value: final dto):
        return Result.ok(_mapTranscriptionDtoToModel(dto));
      case Error(error: final error):
        return Result.error(error);
    }
  }

  Future<Result<Transcription>> transcribeYoutube({
    required String youtubeUrl,
    String? audioLanguage,
    String? summaryLanguage,
    String? keywords,
    String? description,
  }) async {
    final result = await _apiService.transcribeYoutube(
      youtubeUrl: youtubeUrl,
      audioLanguage: audioLanguage,
      summaryLanguage: summaryLanguage,
      keywords: keywords,
      description: description,
    );
    return switch (result) {
      Ok(value: final dto) => Result.ok(_mapTranscriptionDtoToModel(dto)),
      Error(error: final error) => Result.error(error),
    };
  }

  Future<Result<Transcription>> transcriptById(String minuteId) async {
    final result = await _apiService.transcriptById(minuteId);
    return switch (result) {
      Ok(value: final dto) => Result.ok(_mapTranscriptionDtoToModel(dto)),
      Error(error: final error) => Result.error(error),
    };
  }

  // Q&A
  Future<Result<Question>> postShortQuestions({required String minuteId, required String languageCode}) async {
    final result = await _apiService.postShortQuestions(minuteId: minuteId, languageCode: languageCode);
    return switch (result) {
      Ok(value: final dto) => Result.ok(Question(shortQuestions: dto.shortQuestions)),
      Error(error: final error) => Result.error(error),
    };
  }

  Future<Result<Chat>> postChat({
    required String minuteId,
    required String question,
    String? languageCode,
    String? summaryText,
  }) async {
    final result = await _apiService.postChat(
      minuteId: minuteId,
      question: question,
      languageCode: languageCode,
      summaryText: summaryText,
    );
    return switch (result) {
      Ok(value: final dto) => Result.ok(Chat(question: dto.question, answer: dto.answer, minuteId: dto.minuteId)),
      Error(error: final error) => Result.error(error),
    };
  }

  Future<Result<OneAiUser>> getUserInfo() async {
    final result = await _apiService.getUserInfo();
    return switch (result) {
      Ok(value: final dto) => Result.ok(_mapOneAiUserDtoToModel(dto)),
      Error(error: final error) => Result.error(error),
    };
  }

  // Helper methods
  Transcription _mapTranscriptionDtoToModel(TranscriptionDto dto) => Transcription(
    minuteId: dto.minuteId,
    transcription: dto.transcription == null
        ? null
        : TranscriptionDetails(
            duration: dto.transcription?.duration,
            languageCode: dto.transcription?.language_code,
            transcript: dto.transcription?.transcript,
            languageProbability: dto.transcription?.language_probability,
            sections: dto.transcription?.sections
                ?.map((s) => TranscriptionSection(timeRange: s.timeRange, title: s.title, speaker: s.speaker))
                .toList(),
          ),
    description: dto.description,
    keywords: dto.keywords,
    title: dto.title,
  );

  MinuteResponse _mapMinuteResponseDtoToModel(MinuteResponseDto dto) => MinuteResponse(
    total: dto.total,
    data: dto.data.map(_mapMinuteDtoToModel).toList(),
    nextPageCursor: dto.nextPageCursor,
  );

  Minute _mapMinuteDtoToModel(MinuteDto dto) => Minute(
    id: dto.minuteId,
    title: dto.title,
    summaryLanguage: dto.summaryLanguage,
    keywords: dto.keywords,
    transcription: dto.transcription == null
        ? null
        : TranscriptionDetails(
            duration: dto.transcription?.duration,
            languageCode: dto.transcription?.language_code,
            transcript: dto.transcription?.transcript,
            languageProbability: dto.transcription?.language_probability,
            sections: dto.transcription?.sections
                ?.map(
                  (s) => TranscriptionSection(
                    timeRange: s.timeRange,
                    title: s.title,
                    speaker: s.speaker,
                    speakerId: s.speakerId,
                  ),
                )
                .toList(),
          ),
    descriptionAudio: dto.descriptionAudio,
    gcsUri: dto.gcsUri,
    createdAt: dto.createdAt,
    tags: dto.tags,
    type: dto.type,
    iconAsset: dto.iconAsset,
    shortQuestions: dto.shortQuestions,
    summary: dto.summary == null ? null : _mapSummaryDtoToModel(dto.summary!),
    duration: dto.duration,
    speakers: dto.speakers,
  );

  Summary _mapSummaryDtoToModel(SummaryDto dto) => Summary(
    summaryText: dto.summaryText,
    icon: dto.icon,
    title: dto.title,
    type: dto.type,
    sections: dto.sections
        ?.map((SummarySectionDto s) => SummarySection(title: s.title, timeRange: s.timeRange, bullets: s.bullets))
        .toList(),
  );

  OneAiUser _mapOneAiUserDtoToModel(OneAiUserDto dto) =>
      OneAiUser(uid: dto.uid, email: dto.email, role: dto.role, plan: dto.plan, credit: dto.credit);

  Future<Result<Map<String, String>>> getSpeakers({required String minuteId}) => _apiService.getSpeakers(minuteId);

  Future<Result<void>> updateSpeakers({required String minuteId, required String speakerId, required String newName}) =>
      _apiService.updateSpeakerById(minuteId, speakerId, newName);
}
