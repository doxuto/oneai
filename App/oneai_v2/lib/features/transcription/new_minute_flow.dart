import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/models/transcribe_models.dart';
import 'package:one_ai/data/repositories/transcription_repository.dart';
import 'package:one_ai/features/transcription/new_minute_gateway.dart';
import 'package:uuid/uuid.dart';

// ---- Input ----

/// What the record / upload screens hand to `/audioProcessing`. Immutable so
/// it can be a family argument.
class NewMinuteRequest {
  const NewMinuteRequest({
    required this.file,
    required this.fileName,
    required this.sizeBytes,
    required this.contentType,
    required this.options,
  });

  final File file;
  final String fileName;
  final int sizeBytes;
  final String contentType;
  final TranscriptionOptions options;

  SourceType get sourceType => TranscriptionRepository.sourceTypeFor(contentType);

  @override
  bool operator ==(Object other) =>
      other is NewMinuteRequest && other.file.path == file.path && other.fileName == fileName && other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(file.path, fileName, sizeBytes);
}

// ---- State ----

enum NewMinutePhase { creating, uploading, starting, processing }

/// The processing screen renders exactly one of these. v1 animated a fake bar
/// and gave up after ~250s; here every transition is a real event.
sealed class NewMinuteState {
  const NewMinuteState();
  String? get minuteId => null;
  bool get isTerminal => false;
}

final class NewMinuteCreating extends NewMinuteState {
  const NewMinuteCreating();
}

final class NewMinuteUploading extends NewMinuteState {
  const NewMinuteUploading(this.id, this.progress);
  final String id;
  final UploadProgress progress;
  @override
  String get minuteId => id;
}

final class NewMinuteStarting extends NewMinuteState {
  const NewMinuteStarting(this.id);
  final String id;
  @override
  String get minuteId => id;
}

final class NewMinuteProcessing extends NewMinuteState {
  const NewMinuteProcessing(this.id, this.status);
  final String id;

  /// queued | transcribing | summarizing — the UI maps each to a step label.
  final MinuteStatus status;
  @override
  String get minuteId => id;
}

final class NewMinuteReady extends NewMinuteState {
  const NewMinuteReady(this.id, this.title);
  final String id;
  final String title;
  @override
  String get minuteId => id;
  @override
  bool get isTerminal => true;
}

final class NewMinuteCancelled extends NewMinuteState {
  const NewMinuteCancelled(this.id);
  final String? id;
  @override
  String? get minuteId => id;
  @override
  bool get isTerminal => true;
}

final class NewMinuteFailed extends NewMinuteState {
  const NewMinuteFailed({
    required this.phase,
    required this.error,
    required this.retryable,
    this.id,
    this.serverFailure,
  });

  final String? id;
  final NewMinutePhase phase;

  /// [ApiFailure] for callables, the Storage exception for uploads,
  /// [FileTooLargeFailure] for the local size check.
  final Object error;

  /// True when `retry()` can resume from [phase] without a second charge.
  final bool retryable;

  /// Present when the worker itself failed (status `failed`); the credit has
  /// already been refunded server-side.
  final MinuteFailure? serverFailure;

  @override
  String? get minuteId => id;
  @override
  bool get isTerminal => true;

  ApiFailure? get apiFailure => error is ApiFailure ? error as ApiFailure : null;
  bool get isOutOfCredits => error is QuotaFailure && (error as QuotaFailure).isCredits;
  DateTime? get creditsResetAt => error is QuotaFailure ? (error as QuotaFailure).resetAt : null;
  bool get needsAppUpdate => error is PreconditionFailure && (error as PreconditionFailure).needsAppUpdate;
}

/// Raised locally before any network call when the picked file exceeds the
/// limit the server advertised in `createMinute`.
class FileTooLargeFailure implements Exception {
  const FileTooLargeFailure({required this.sizeBytes, required this.maxSizeBytes});
  final int sizeBytes;
  final int maxSizeBytes;
}

// ---- Wiring ----

final newMinuteGatewayProvider = Provider<NewMinuteGateway>(
  (ref) => RepositoryNewMinuteGateway(
    minutes: ref.watch(minutesRepositoryProvider),
    transcription: ref.watch(transcriptionRepositoryProvider),
    uid: ref.watch(currentUidProvider),
  ),
);

final newMinuteFlowProvider =
    NotifierProvider.autoDispose.family<NewMinuteFlow, NewMinuteState, NewMinuteRequest>(NewMinuteFlow.new);

// ---- Controller ----

class NewMinuteFlow extends Notifier<NewMinuteState> {
  NewMinuteFlow(this.request);

  final NewMinuteRequest request;

  /// One id for the whole flow so retrying `start` can never charge twice —
  /// the server treats a repeated requestId as the same job.
  late final String _requestId = const Uuid().v4();

  CreateMinuteResult? _target;
  StreamSubscription<Object?>? _sub;
  bool _cancelRequested = false;

  NewMinuteGateway get _gw => ref.read(newMinuteGatewayProvider);

  @override
  NewMinuteState build() {
    ref.onDispose(() => unawaited(_sub?.cancel()));
    // Kick off after build returns so the first state is observable.
    unawaited(Future<void>.microtask(_create));
    return const NewMinuteCreating();
  }

  // ---- Steps ----

  Future<void> _create() async {
    state = const NewMinuteCreating();
    final CreateMinuteResult target;
    try {
      target = await _gw.createMinute(
        sourceType: request.sourceType,
        fileName: request.fileName,
        sizeBytes: request.sizeBytes,
        contentType: request.contentType,
      );
    } on Object catch (e) {
      _fail(NewMinutePhase.creating, e, retryable: e is ApiFailure ? e.isRetryable : true);
      return;
    }
    _target = target;
    if (_cancelRequested) {
      await _abandon(target.minuteId);
      return;
    }
    if (request.sizeBytes > target.maxSizeBytes) {
      await _guarded(() => _gw.deleteMinute(target.minuteId));
      _fail(
        NewMinutePhase.creating,
        FileTooLargeFailure(sizeBytes: request.sizeBytes, maxSizeBytes: target.maxSizeBytes),
        retryable: false,
      );
      return;
    }
    _upload(target);
  }

  void _upload(CreateMinuteResult target) {
    state = NewMinuteUploading(target.minuteId, const UploadProgress(bytesTransferred: 0, totalBytes: 0));
    unawaited(_sub?.cancel());
    _sub = _gw.upload(file: request.file, target: target).listen(
      (p) {
        if (state is NewMinuteUploading) state = NewMinuteUploading(target.minuteId, p);
      },
      onError: (Object e) {
        if (_cancelRequested) {
          // Our own cancel() surfaces as an error on the task stream.
          unawaited(_abandon(target.minuteId));
          return;
        }
        _fail(NewMinutePhase.uploading, e, retryable: true, id: target.minuteId);
      },
      onDone: () {
        if (_cancelRequested) {
          unawaited(_abandon(target.minuteId));
          return;
        }
        if (state is NewMinuteUploading) unawaited(_start(target.minuteId));
      },
      cancelOnError: true,
    );
  }

  Future<void> _start(String minuteId) async {
    state = NewMinuteStarting(minuteId);
    try {
      await _gw.start(minuteId: minuteId, options: request.options, requestId: _requestId);
    } on Object catch (e) {
      // Quota / precondition are final; transient ones may be retried with
      // the same requestId (idempotent on the server).
      _fail(NewMinutePhase.starting, e, retryable: e is ApiFailure && e.isRetryable, id: minuteId);
      return;
    }
    if (_cancelRequested) {
      await _guarded(() => _gw.cancelTranscription(minuteId));
    }
    _watch(minuteId);
  }

  void _watch(String minuteId) {
    state = NewMinuteProcessing(minuteId, MinuteStatus.queued);
    unawaited(_sub?.cancel());
    _sub = _gw.watchProgress(minuteId).listen(
      (p) {
        switch (p.status) {
          case MinuteStatus.ready:
            state = NewMinuteReady(minuteId, p.title);
            unawaited(_sub?.cancel());
          case MinuteStatus.failed:
            state = NewMinuteFailed(
              id: minuteId,
              phase: NewMinutePhase.processing,
              error: p.failure ?? const MinuteFailure(code: 'unknown', message: ''),
              retryable: false,
              serverFailure: p.failure,
            );
            unawaited(_sub?.cancel());
          case MinuteStatus.cancelled:
            state = NewMinuteCancelled(minuteId);
            unawaited(_sub?.cancel());
          case MinuteStatus.queued:
          case MinuteStatus.transcribing:
          case MinuteStatus.summarizing:
            state = NewMinuteProcessing(minuteId, p.status);
          case MinuteStatus.uploading:
          case MinuteStatus.unknown:
            // Stale or unrecognised — keep showing the last known step.
            break;
        }
      },
      onError: (Object e) {
        // Losing the listener is not losing the job: the worker keeps going.
        // Report as transient so the screen offers "reconnect".
        _fail(NewMinutePhase.processing, e, retryable: true, id: minuteId);
      },
    );
  }

  // ---- User actions ----

  /// Cancels whatever is in flight. Before the job is queued the minute is
  /// deleted (nothing was charged); after that the server refunds.
  Future<void> cancel() async {
    if (state.isTerminal) return;
    _cancelRequested = true;
    switch (state) {
      case NewMinuteCreating():
        // _create() checks the flag when createMinute returns.
        break;
      case NewMinuteUploading(:final id):
        await _gw.cancelUpload();
        await _abandon(id);
      case NewMinuteStarting():
        // _start() checks the flag after the callable returns.
        break;
      case NewMinuteProcessing(:final id):
        try {
          await _gw.cancelTranscription(id);
          // The Firestore listener flips us to NewMinuteCancelled.
        } on PreconditionFailure catch (_) {
          // Already terminal on the server; the listener will say which.
        } on Object catch (e) {
          _fail(NewMinutePhase.processing, e, retryable: true, id: id);
        }
      case NewMinuteReady() || NewMinuteCancelled() || NewMinuteFailed():
        break;
    }
  }

  /// Resumes from the phase that failed. No-op unless `retryable`.
  Future<void> retry() async {
    final s = state;
    if (s is! NewMinuteFailed || !s.retryable) return;
    _cancelRequested = false;
    _abandoning = false;
    switch (s.phase) {
      case NewMinutePhase.creating:
        await _create();
      case NewMinutePhase.uploading:
        final t = _target;
        if (t == null) {
          await _create();
        } else {
          _upload(t);
        }
      case NewMinutePhase.starting:
        await _start(s.id!);
      case NewMinutePhase.processing:
        _watch(s.id!);
    }
  }

  // ---- Helpers ----

  bool _abandoning = false;

  Future<void> _abandon(String minuteId) async {
    // cancel() and the upload stream's onError both land here; delete once.
    if (_abandoning || state is NewMinuteCancelled) return;
    _abandoning = true;
    unawaited(_sub?.cancel());
    await _guarded(() => _gw.deleteMinute(minuteId));
    state = NewMinuteCancelled(minuteId);
  }

  void _fail(NewMinutePhase phase, Object error, {required bool retryable, String? id}) {
    dev.log('new minute failed at ${phase.name}', name: 'transcription', error: error);
    state = NewMinuteFailed(id: id, phase: phase, error: error, retryable: retryable);
  }

  Future<void> _guarded(Future<void> Function() op) async {
    try {
      await op();
    } on Object catch (e) {
      dev.log('ignored', name: 'transcription', error: e);
    }
  }
}
