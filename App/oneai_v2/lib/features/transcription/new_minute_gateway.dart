import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/models/transcribe_models.dart';
import 'package:one_ai/data/repositories/minutes_repository.dart';
import 'package:one_ai/data/repositories/transcription_repository.dart';

/// Everything the new-minute flow needs from the outside world, as one
/// interface so the state machine can be tested with a single fake. The
/// production implementation just forwards to the two repositories.
abstract interface class NewMinuteGateway {
  Future<CreateMinuteResult> createMinute({
    required SourceType sourceType,
    required String fileName,
    required int sizeBytes,
    required String contentType,
  });

  /// Emits progress until the upload completes, then closes. Errors close it.
  Stream<UploadProgress> upload({required File file, required CreateMinuteResult target});

  /// S11-09: uploads the chunks of a recording one after another to
  /// `source/parts/part-NNN.<ext>`; progress is over the total bytes.
  Stream<UploadProgress> uploadParts({required List<File> parts, required CreateMinuteResult target});

  /// Aborts the in-flight upload started by [upload], if any. Idempotent.
  Future<void> cancelUpload();

  Future<StartTranscriptionResult> start({
    required String minuteId,
    required TranscriptionOptions options,
    required String requestId,
    int? partCount,
  });

  Future<void> cancelTranscription(String minuteId);

  /// Best-effort cleanup when the user abandons the flow before it is queued.
  Future<void> deleteMinute(String minuteId);

  Stream<MinuteProgress> watchProgress(String minuteId);
}

class RepositoryNewMinuteGateway implements NewMinuteGateway {
  RepositoryNewMinuteGateway({
    required MinutesRepository minutes,
    required TranscriptionRepository transcription,
    required String uid,
  })  : _minutes = minutes,
        _transcription = transcription,
        _uid = uid;

  final MinutesRepository _minutes;
  final TranscriptionRepository _transcription;
  final String _uid;
  UploadTask? _task;

  @override
  Future<CreateMinuteResult> createMinute({
    required SourceType sourceType,
    required String fileName,
    required int sizeBytes,
    required String contentType,
  }) =>
      _minutes.create(sourceType: sourceType, fileName: fileName, sizeBytes: sizeBytes, contentType: contentType);

  @override
  Stream<UploadProgress> upload({required File file, required CreateMinuteResult target}) {
    final task = _task = _transcription.upload(file: file, target: target);
    // snapshotEvents completes when the task settles; a cancelled or failed
    // task surfaces as a FirebaseException on the stream.
    return task.snapshotEvents.map(
      (s) => UploadProgress(bytesTransferred: s.bytesTransferred, totalBytes: s.totalBytes),
    );
  }

  @override
  Stream<UploadProgress> uploadParts({required List<File> parts, required CreateMinuteResult target}) async* {
    final total = parts.fold<int>(0, (n, f) => n + (f.existsSync() ? f.lengthSync() : 0));
    var done = 0;
    for (var i = 0; i < parts.length; i++) {
      final task = _task = _transcription.uploadPart(file: parts[i], index: i, target: target);
      await for (final s in task.snapshotEvents) {
        yield UploadProgress(bytesTransferred: done + s.bytesTransferred, totalBytes: total);
      }
      done += parts[i].lengthSync();
    }
    _task = null;
  }

  @override
  Future<void> cancelUpload() async {
    final t = _task;
    _task = null;
    if (t == null) return;
    try {
      await t.cancel();
    } on Object catch (_) {
      // Already finished — nothing to cancel.
    }
  }

  @override
  Future<StartTranscriptionResult> start({
    required String minuteId,
    required TranscriptionOptions options,
    required String requestId,
    int? partCount,
  }) =>
      _transcription.start(minuteId: minuteId, options: options, requestId: requestId, partCount: partCount);

  @override
  Future<void> cancelTranscription(String minuteId) => _transcription.cancel(minuteId);

  @override
  Future<void> deleteMinute(String minuteId) => _minutes.delete(minuteId);

  @override
  Stream<MinuteProgress> watchProgress(String minuteId) => _minutes.watchProgress(_uid, minuteId);
}
