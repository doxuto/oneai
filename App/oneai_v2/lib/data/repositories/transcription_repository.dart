import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:one_ai/data/firebase/functions_client.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/models/transcribe_models.dart';
import 'package:uuid/uuid.dart';

/// Upload progress as the Storage SDK reports it. `fraction` is 0..1.
class UploadProgress {
  const UploadProgress({required this.bytesTransferred, required this.totalBytes});
  final int bytesTransferred;
  final int totalBytes;
  double get fraction => totalBytes == 0 ? 0 : bytesTransferred / totalBytes;
}

/// The three-step v2 flow: createMinute → upload directly to Storage →
/// startTranscription. The worker does the rest; watch progress via
/// MinutesRepository.watchProgress.
class TranscriptionRepository {
  TranscriptionRepository({required FunctionsClient functions, required FirebaseStorage storage, Uuid? uuid})
      : _fns = functions,
        _storage = storage,
        _uuid = uuid ?? const Uuid();

  final FunctionsClient _fns;
  final FirebaseStorage _storage;
  final Uuid _uuid;

  /// Resumable upload. Returns the task so the UI can show real progress,
  /// pause, resume or cancel — v1 showed a fake bar and could not cancel.
  UploadTask upload({required File file, required CreateMinuteResult target}) =>
      _storage.ref(target.uploadPath).putFile(file, SettableMetadata(contentType: target.contentType));

  /// S11-09: chunk `index` of a chunked recording → `source/parts/part-NNN.<ext>`
  /// next to the final path; the worker joins them into `uploadPath`.
  UploadTask uploadPart({required File file, required int index, required CreateMinuteResult target}) =>
      _storage.ref(partPathFor(target.uploadPath, index)).putFile(file, SettableMetadata(contentType: target.contentType));

  static String partPathFor(String uploadPath, int index) {
    final slash = uploadPath.lastIndexOf('/');
    final dir = uploadPath.substring(0, slash);
    final name = uploadPath.substring(slash + 1);
    final ext = name.contains('.') ? name.split('.').last : 'm4a';
    return '$dir/parts/part-${index.toString().padLeft(3, '0')}.$ext';
  }

  Future<StartTranscriptionResult> start({required String minuteId, required TranscriptionOptions options, String? requestId, int? partCount}) async {
    final tz = await FlutterTimezone.getLocalTimezone();
    return StartTranscriptionResult.fromJson(await _fns.call('startTranscription', {
      'minuteId': minuteId,
      'requestId': requestId ?? _uuid.v4(),
      'audioLanguage': options.audioLanguage,
      'summaryLanguage': options.summaryLanguage,
      'keywords': options.keywords,
      if (options.description != null) 'description': options.description,
      'template': options.template.wire,
      'timezone': tz,
      if (options.durationSeconds != null) 'durationSeconds': options.durationSeconds,
      if (partCount != null && partCount > 1) 'partCount': partCount,
    }));
  }

  Future<void> cancel(String minuteId) => _fns.call('cancelTranscription', {'minuteId': minuteId});

  /// Download URL for the source audio (or PDF) of a note, via the caller's own
  /// Storage auth — the server hands out paths, never signed URLs.
  Future<String> downloadUrl(String storagePath) => _storage.ref(storagePath).getDownloadURL();

  /// Copies the source file to [target] (for "share audio file").
  Future<File> downloadSource(String storagePath, File target) async {
    await _storage.ref(storagePath).writeToFile(target);
    return target;
  }

  /// Convenience for the record/upload screens: pick the source type from the file.
  static SourceType sourceTypeFor(String contentType) =>
      contentType.toLowerCase() == 'application/pdf' ? SourceType.pdf : SourceType.audio;
}
