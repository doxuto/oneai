import 'dart:async';

import 'package:codebase_ai/data/repositories/oneai_repository.dart';
import 'package:codebase_ai/domain/models/minute_model.dart';
import 'package:codebase_ai/domain/models/transcription_model.dart';
import 'package:codebase_ai/utils/result.dart';

class MinuteUseCase {
  final OneAiRepository _repository;
  final StreamController<List<Minute>> _minutesController = StreamController.broadcast();
  List<Minute> _minutesCache = [];

  static const _pageSize = 10;

  static const _initialStartAfterDocId = '';

  // empty if initial load
  // not empty if load more
  // null if last page cursor
  String? _startAfterDocId = _initialStartAfterDocId;

  List<Minute> get minutes => List.unmodifiable(_minutesCache);

  MinuteUseCase(this._repository);

  Stream<List<Minute>> get minutesStream async* {
    if (_minutesCache.isNotEmpty) {
      yield List<Minute>.from(_minutesCache);
    }
    yield* _minutesController.stream;
  }

  void _setMinutes(List<Minute> minutes) {
    _minutesCache = minutes;
    _minutesController.add(_minutesCache);
  }

  Future<Result<MinuteResponse>> _getMinutes({String? startAfterDocId, int limit = _pageSize}) =>
      _repository.getMinutes(startAfterDocId: startAfterDocId, limit: limit);

  Future<Result<void>> loadMinutes({required bool isRefresh, required bool isLoadMore}) async {
    if (isRefresh) {
      _startAfterDocId = _initialStartAfterDocId;
      _minutesCache = [];
    }

    // end cursor of list, not call api, return success
    if (_startAfterDocId == null) {
      return const Result.ok(null);
    }

    final startAfter = _startAfterDocId == _initialStartAfterDocId ? null : _startAfterDocId;

    final result = await _getMinutes(startAfterDocId: startAfter);

    if (result is Ok<MinuteResponse>) {
      final minutes = isLoadMore ? [..._minutesCache, ...result.value.data] : result.value.data;
      _setMinutes(minutes);
      _startAfterDocId = result.value.nextPageCursor;
    } else {
      // When error, sync with cache
      _setMinutes(_minutesCache);
    }
    return result;
  }

  Future<Result<Minute>> getMinuteById(String minuteId) async => _repository.getMinuteById(minuteId);

  Future<Result<void>> updateMinuteById(String minuteId, {String? title, String? iconAsset, List<String>? tags}) async {
    final result = await _repository.updateMinuteById(minuteId, title: title, iconAsset: iconAsset, tags: tags);
    if (result is Ok) {
      Minute minuteUpdate = _minutesCache.firstWhere((minute) => minute.id == minuteId);
      if (title != null) {
        minuteUpdate = minuteUpdate.copyWith(title: title);
      }
      if (iconAsset != null) {
        minuteUpdate = minuteUpdate.copyWith(iconAsset: iconAsset);
      }
      if (tags != null) {
        minuteUpdate = minuteUpdate.copyWith(tags: tags);
      }

      _setMinutes(_minutesCache.map((minute) => minute.id == minuteId ? minuteUpdate : minute).toList());
    }
    return result;
  }

  Future<Result<void>> deleteMinuteById(String minuteId) async {
    final result = await _repository.deleteMinuteById(minuteId);
    if (result is Ok) {
      _setMinutes(_minutesCache.where((minute) => minute.id != minuteId).toList());
    }
    return result;
  }

  Future<Result<Transcription>> transcribe({
    required String filePath,
    String? audioLanguage,
    String? summaryLanguage,
    String? keywords,
    String? description,
  }) async {
    final result = await _repository.transcribe(
      filePath: filePath,
      audioLanguage: audioLanguage,
      summaryLanguage: summaryLanguage,
      keywords: keywords,
      description: description,
    );
    if (result is Ok<Transcription>) {
      // Get first item in list
      final newMinute = await _getMinutes(limit: 1);
      if (newMinute is Ok<MinuteResponse>) {
        _setMinutes([...newMinute.value.data, ..._minutesCache]);
      }
    }

    return result;
  }

  Future<Result<Transcription>> transcribeYoutube({
    required String youtubeUrl,
    String? audioLanguage,
    String? summaryLanguage,
    String? keywords,
    String? description,
  }) async {
    final result = await _repository.transcribeYoutube(
      youtubeUrl: youtubeUrl,
      audioLanguage: audioLanguage,
      summaryLanguage: summaryLanguage,
      keywords: keywords,
      description: description,
    );
    if (result is Ok<Transcription>) {
      // Get first item in list
      final newMinute = await _getMinutes(limit: 1);
      if (newMinute is Ok<MinuteResponse>) {
        _setMinutes([...newMinute.value.data, ..._minutesCache]);
      }
    }

    return result;
  }

  Future<Result<void>> updateSpeakers({required String minuteId, required String speakerId, required String newName}) =>
      _repository.updateSpeakers(minuteId: minuteId, speakerId: speakerId, newName: newName);

  void dispose() {
    _minutesController.close();
  }
}
