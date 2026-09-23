import 'package:flutter/widgets.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/features/auth/auth_models.dart';
import 'package:one_ai/features/transcription/new_minute_flow.dart';

/// The ONE place an error becomes words. Everything the UI shows for a
/// failure goes through here, so wording is consistent and localized.
String failureText(BuildContext context, Object? error) {
  final l = context.l10n;
  return switch (error) {
    null => l.somethingWentWrong,
    QuotaFailure(:final resetAt, :final reason) => switch (reason) {
        'aiDailyLimit' => l.aiDailyLimitReached(resetAt == null ? '--:--' : _time(context, resetAt)),
        'tooManyActiveJobs' => l.waitForCurrentRecording,
        _ => resetAt == null ? l.noFreeMinutesLeft : '${l.noFreeMinutesLeft} ${l.quotaMinutesResetsAt(_time(context, resetAt))}',
      },
    PreconditionFailure(:final minVersion) when minVersion != null => l.updateRequired,
    PreconditionFailure(:final reason, :final limitSeconds) => switch (reason) {
        'notReady' => l.noteNotReady,
        'noSpeech' => l.noSpeechDetected,
        'durationLimit' => l.recordingTooLong(((limitSeconds ?? 600) / 60).round()),
        'quota' => l.noFreeMinutesLeft,
        'tooManyActiveJobs' => l.waitForCurrentRecording,
        _ => l.somethingWentWrong,
      },
    NotFoundFailure() => l.notFound,
    TransientFailure() => l.connectToInternet,
    AuthFailure() || PermissionFailure() => l.somethingWentWrong,
    ValidationFailure() || ConflictFailure() || ServerFailure() => l.somethingWentWrong,
    SignInNetwork() => l.connectToInternet,
    SignInFailure() => l.somethingWentWrong,
    FileTooLargeFailure() => l.uploadFailed,
    _ => l.somethingWentWrong,
  };
}

String _time(BuildContext context, DateTime t) {
  final local = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
