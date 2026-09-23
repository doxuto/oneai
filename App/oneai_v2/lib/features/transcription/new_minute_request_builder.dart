import 'dart:io';

import 'package:one_ai/data/models/transcribe_models.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/transcription/new_minute_flow.dart';
import 'package:one_ai/features/transcription/prompt_language_sheet.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';

/// From a picked/recorded file + the sheet's settings to what `/audioProcessing` needs.
/// `parts` (S11-09): the chunks of a chunked recording, `file` being the first.
NewMinuteRequest buildNewMinuteRequest({required File file, required PromptSettings settings, double? durationSeconds, List<File> parts = const []}) {
  final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : 'audio.m4a';
  final all = parts.length > 1 ? parts : [file];
  return NewMinuteRequest(
    file: file,
    parts: parts.length > 1 ? parts : const [],
    fileName: name,
    sizeBytes: all.fold<int>(0, (n, f) => n + (f.existsSync() ? f.lengthSync() : 0)),
    contentType: contentTypeFor(name),
    options: TranscriptionOptions(
      summaryLanguage: settings.summaryLanguage.englishName,
      audioLanguage: settings.audioLanguage.code,
      keywords: settings.keywordList,
      description: settings.description.isEmpty ? null : settings.description,
      template: settings.template,
      durationSeconds: durationSeconds,
    ),
  );
}

/// The server validates against storage.rules (`audio/*` or `application/pdf`).
String contentTypeFor(String fileName) {
  final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'm4a' => 'audio/x-m4a',
    'mp3' => 'audio/mpeg',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'flac' => 'audio/flac',
    'webm' => 'audio/webm',
    'mp4' => 'audio/mp4',
    'aiff' || 'aif' => 'audio/aiff',
    'pdf' => 'application/pdf',
    _ => 'audio/mpeg',
  };
}

PromptSettings defaultPromptSettings(LanguageSettings s) =>
    PromptSettings(audioLanguage: s.audioLanguage, summaryLanguage: s.summaryLanguage == TranscriptionLanguage.auto ? TranscriptionLanguage.english : s.summaryLanguage);
