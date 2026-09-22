import 'dart:io';
import 'package:codebase_ai/data/services/model/oneai/chat_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/minute_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/question_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/tag_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/transcription_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/user_dto.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';

/// Service for interacting with OneAI backend API
class OneAiApiService {
  final Dio _dio;
  final _log = Logger('OneAiApiService');

  /// Provide a Dio client and optionally an auth token
  OneAiApiService({Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://us-central1-minutesai-6715a.cloudfunctions.net/api/v1')) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _log.info('${options.method} ${options.uri}');
          if (options.data != null) {
            _log.info('Request data: ${options.data}');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          _log.info('${response.statusCode} ${response.requestOptions.uri}');
          _log.info('Response data: ${response.data}');
          handler.next(response);
        },
        onError: (error, handler) {
          _log.severe(
            'Error ${error.response?.statusCode ?? 'unknown'} ${error.requestOptions.uri}',
            error.error,
            error.stackTrace,
          );
          handler.next(error);
        },
      ),
    );
  }

  String _formatTimeZoneOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$sign$hours:$minutes';
  }

  Future<Options> _optionsWithAuth() async {
    final token = await FirebaseAuth.instance.currentUser!.getIdToken();
    _log.info('Token: $token');
    String platform;
    if (Platform.isIOS) {
      platform = 'iOS';
    } else if (Platform.isAndroid) {
      platform = 'Android';
    } else {
      platform = 'Unknown';
    }

    // get Timezone and offset
    final timezoneName = DateTime.now().timeZoneName; // e.g., 'Asia/Ho_Chi_Minh'
    _log.info('Timezone: $timezoneName');
    final timezoneOffset = _formatTimeZoneOffset(DateTime.now().timeZoneOffset); // e.g., '+07:00' or '-05:00'
    _log.info('Timezone Offset: $timezoneOffset');

    return Options(
      headers: {
        'Authorization': 'Bearer $token',
        'X-Timezone': timezoneName,
        'X-Timezone-Offset': timezoneOffset,
        'X-Language': 'en-US',
        'X-Platform': platform,
      },
    );
  }

  // ---------- TAGS ----------

  /// Create a tag
  Future<Result<TagDto>> createTag(String name) async {
    try {
      final response = await _dio.post('/tags', data: {'name': name}, options: await _optionsWithAuth());

      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null) {
        return Result.error(Exception('Failed to create tag: ${response.data['message'] ?? 'No data'}'));
      }
      return Result.ok(TagDto.fromJson(Map<String, dynamic>.from(response.data['data'] as Map)));
    } on DioException catch (e) {
      return Result.error(Exception('Failed to create tag: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to create tag: $e'));
    }
  }

  /// Update a tag
  Future<Result<TagDto>> updateTag(String tagId, String name) async {
    try {
      final response = await _dio.put('/tags/$tagId', data: {'name': name}, options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null) {
        return Result.error(Exception('Failed to update tag: ${response.data['message'] ?? 'No data'}'));
      }
      final data = response.data['data'] as Map<String, dynamic>;
      final tag = TagDto(id: data['tagId'] as String, name: data['name'] as String);
      return Result.ok(tag);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to update tag: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to update tag: $e'));
    }
  }

  /// Delete a tag
  Future<Result<void>> deleteTag(String tagId) async {
    try {
      final response = await _dio.delete('/tags/$tagId', options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success) {
        return Result.error(Exception('Failed to delete tag: ${response.data['message'] ?? 'No data'}'));
      }
      return const Result.ok(null);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to delete tag: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to delete tag: $e'));
    }
  }

  /// Get all tags
  Future<Result<List<TagDto>>> getAllTags() async {
    try {
      final response = await _dio.get('/tags', options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null || response.data['data']['tags'] == null) {
        return Result.error(Exception('Failed to fetch tags: ${response.data['message'] ?? 'No data'}'));
      }
      final tagsJson = response.data['data']['tags'] as List<dynamic>;
      final tags = tagsJson.map((j) => TagDto.fromJson(Map<String, dynamic>.from(j as Map))).toList();
      return Result.ok(tags);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to fetch tags: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to fetch tags: $e'));
    }
  }

  // ---------- MINUTES ----------

  /// Get a minute by ID
  Future<Result<MinuteDto>> getMinuteById(String minuteId) async {
    try {
      final response = await _dio.get('/minutes/$minuteId', options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null) {
        return Result.error(Exception('Failed to fetch minute: ${response.data['message'] ?? 'No data'}'));
      }
      final map = Map<String, dynamic>.from(response.data['data'] as Map<dynamic, dynamic>);
      final minute = MinuteDto.fromJson(map);
      return Result.ok(minute);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to fetch minute: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to fetch minute: $e'));
    }
  }

  /// Get all minutes
  Future<Result<MinuteResponseDto>> getMinutes({String? startAfterDocId, int limit = 10}) async {
    try {
      final queryParameters = {'limit': limit.toString()};
      if (startAfterDocId != null) {
        queryParameters['startAfterDocId'] = startAfterDocId;
      }

      final response = await _dio.get('/minutes', queryParameters: queryParameters, options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null || response.data['data']['data'] == null) {
        return Result.error(Exception('Failed to fetch minutes: ${response.data['message'] ?? 'No data'}'));
      }
      final dataList = response.data['data']['data'] as List<dynamic>;
      final list = dataList
          .map((j) => MinuteDto.fromJson(Map<String, dynamic>.from(j as Map<dynamic, dynamic>)))
          .toList();
      return Result.ok(
        MinuteResponseDto(
          total: response.data['data']['total'] as int,
          data: list,
          nextPageCursor: response.data['data']['nextPageCursor'] as String?,
        ),
      );
    } on DioException catch (e) {
      return Result.error(Exception('Failed to fetch minutes: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to fetch minutes: $e'));
    }
  }

  /// Update a minute by ID
  Future<Result<void>> updateMinuteById(String minuteId, {String? title, String? iconAsset, List<String>? tags}) async {
    try {
      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title;
      if (iconAsset != null) payload['iconAsset'] = iconAsset;
      if (tags != null) payload['tags'] = tags;
      if (payload.isEmpty) {
        return Result.error(Exception('No fields provided for update.'));
      }
      final response = await _dio.patch('/minutes/$minuteId', data: payload, options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success) {
        return Result.error(Exception('Failed to update minute: ${response.data['message'] ?? 'No data'}'));
      }
      return const Result.ok(null);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to update minute: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to update minute: $e'));
    }
  }

  /// Delete a minute by ID
  Future<Result<void>> deleteMinuteById(String minuteId) async {
    try {
      final response = await _dio.delete('/minutes/$minuteId', options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success) {
        return Result.error(Exception('Failed to delete minute: ${response.data['message'] ?? 'No data'}'));
      }
      return const Result.ok(null);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to delete minute: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to delete minute: $e'));
    }
  }

  // ---------- TRANSCRIPTION ----------

  /// Transcribe audio file
  Future<Result<TranscriptionDto>> transcribe({
    required String filePath,
    String? audioLanguage,
    String? summaryLanguage,
    String? keywords,
    String? description,
  }) async {
    try {
      final formMap = <String, dynamic>{'file': await MultipartFile.fromFile(filePath)};
      if (audioLanguage != null) {
        formMap['audioLanguage'] = audioLanguage;
      }
      if (summaryLanguage != null) {
        formMap['summaryLanguage'] = summaryLanguage;
      }
      if (keywords != null) {
        formMap['keywords'] = keywords;
      }
      if (description != null) {
        formMap['description'] = description;
      }
      final formData = FormData.fromMap(formMap);
      final response = await _dio.post(
        '/transcription/transcribe',
        data: formData,
        options: (await _optionsWithAuth()).copyWith(contentType: 'multipart/form-data'),
      );
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null) {
        return Result.error(Exception('Failed to transcribe: ${response.data['message'] ?? 'No data'}'));
      }
      final map = Map<String, dynamic>.from(response.data['data'] as Map);
      return Result.ok(TranscriptionDto.fromJson(map));
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Transcribe YouTube video
  Future<Result<TranscriptionDto>> transcribeYoutube({
    required String youtubeUrl,
    String? audioLanguage,
    String? summaryLanguage,
    String? keywords,
    String? description,
  }) async {
    try {
      final data = {
        'youtubeUrl': youtubeUrl,
        'audioLanguage': audioLanguage,
        'summaryLanguage': summaryLanguage,
        'keywords': keywords,
        'description': description,
      }..removeWhere((key, value) => value == null);
      final response = await _dio.post('/transcription/youtube', data: data, options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null) {
        return Result.error(Exception('Failed to youtube transcribe: ${response.data['message'] ?? 'No data'}'));
      }
      final map = Map<String, dynamic>.from(response.data['data'] as Map<dynamic, dynamic>);
      return Result.ok(TranscriptionDto.fromJson(map));
    } on Exception catch (e) {
      return Result.error(e);
    }
  }

  /// Get transcription by minute ID
  Future<Result<TranscriptionDto>> transcriptById(String minuteId) async {
    try {
      final response = await _dio.get('/minutes/$minuteId/transcription', options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null) {
        return Result.error(Exception('Failed to fetch transcript: ${response.data['message'] ?? 'No data'}'));
      }
      final map = Map<String, dynamic>.from(response.data['data'] as Map<dynamic, dynamic>);
      return Result.ok(TranscriptionDto.fromJson(map));
    } on DioException catch (e) {
      return Result.error(Exception('Failed to fetch transcript: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to fetch transcript: $e'));
    }
  }

  // ---------- Q&A ----------

  /// Post short questions
  Future<Result<QuestionDto>> postShortQuestions({required String minuteId, required String languageCode}) async {
    try {
      final response = await _dio.post(
        '/minutes/$minuteId/questions',
        data: {'languageCode': languageCode},
        options: await _optionsWithAuth(),
      );
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null || response.data['data']['short_questions'] == null) {
        return Result.error(Exception('Failed to get questions: ${response.data['message'] ?? 'No data'}'));
      }
      final map = Map<String, dynamic>.from(response.data['data'] as Map<dynamic, dynamic>);
      return Result.ok(QuestionDto.fromJson(map));
    } on DioException catch (e) {
      return Result.error(Exception('Failed to get questions: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to get questions: $e'));
    }
  }

  /// Post chat question
  Future<Result<ChatDto>> postChat({
    required String minuteId,
    required String question,
    String? languageCode,
    String? summaryText,
  }) async {
    try {
      final data = <String, dynamic>{'question': question};
      if (languageCode != null) data['languageCode'] = languageCode;
      if (summaryText != null) data['summaryText'] = summaryText;
      final response = await _dio.post('/minutes/$minuteId/chat', data: data, options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null) {
        return Result.error(Exception('Failed to chat: ${response.data['message'] ?? 'No data'}'));
      }
      final map = Map<String, dynamic>.from(response.data['data'] as Map<dynamic, dynamic>);
      return Result.ok(ChatDto.fromJson(map));
    } on DioException catch (e) {
      return Result.error(Exception('Failed to chat: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to chat: $e'));
    }
  }

  /// Get user info
  Future<Result<OneAiUserDto>> getUserInfo() async {
    try {
      final response = await _dio.get('/user/me', options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null || response.data['data']['user'] == null) {
        return Result.error(Exception('Failed to fetch user info: ${response.data['message'] ?? 'No data'}'));
      }
      final map = Map<String, dynamic>.from(response.data['data']['user'] as Map<dynamic, dynamic>);
      return Result.ok(OneAiUserDto.fromJson(map));
    } on DioException catch (e) {
      return Result.error(Exception('Failed to fetch user info: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to fetch user info: $e'));
    }
  }

  Future<Result<Map<String, String>>> getSpeakers(String minuteId) async {
    try {
      final response = await _dio.get('/minutes/$minuteId/speakers', options: await _optionsWithAuth());
      final success = response.data['success'] == true;
      if (!success || response.data['data'] == null || response.data['data']['speakers'] == null) {
        return Result.error(Exception('Failed to fetch speakers: ${response.data['message'] ?? 'No data'}'));
      }
      final speakers = Map<String, String>.from(response.data['data']['speakers'] as Map<dynamic, dynamic>);
      return Result.ok(speakers);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to fetch speakers: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to fetch speakers: $e'));
    }
  }

  Future<Result<void>> updateSpeakerById(String minuteId, String speakerId, String name) async {
    try {
      // final queryParameters = {'newName': Uri.encodeQueryComponent(name)};
      final response = await _dio.patch(
        '/minutes/$minuteId/speakers/$speakerId',
        // queryParameters: queryParameters,
        data: {'newName': name},
        options: await _optionsWithAuth(),
      );
      final success = response.data['success'] == true;
      if (!success) {
        return Result.error(Exception('Failed to update speaker: ${response.data['message'] ?? 'No data'}'));
      }
      return const Result.ok(null);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to update speaker: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to update speaker: $e'));
    }
  }

  /// Call reward API to add credit after rewarded ad
  Future<Result<int>> postRewardedAdCredit({int reward = 1}) async {
    try {
      final response = await _dio.post(
        '/user/reward',
        data: {'rewardAmount': reward},
        options: await _optionsWithAuth(),
      );
      final success = response.data['success'] == true;
      if (!success) {
        return Result.error(Exception('Failed to add credit: ${response.data['message'] ?? 'No data'}'));
      }
      // New response: {success: true, data: {credit: 20}, message: ...}
      final data = response.data['data'];
      final credit = (data is Map && data['credit'] is int) ? data['credit'] as int : null;
      return Result.ok(credit ?? 0);
    } on DioException catch (e) {
      return Result.error(Exception('Failed to add credit: ${e.message}'));
    } on Exception catch (e) {
      return Result.error(Exception('Failed to add credit: $e'));
    }
  }
}
