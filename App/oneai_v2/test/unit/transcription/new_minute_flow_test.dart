import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/minute_models.dart';
import 'package:one_ai/data/models/transcribe_models.dart';
import 'package:one_ai/data/repositories/transcription_repository.dart';
import 'package:one_ai/features/transcription/new_minute_flow.dart';
import 'package:one_ai/features/transcription/new_minute_gateway.dart';

// ---- A scripted gateway: every step is a Completer/StreamController the test drives ----

class FakeGateway implements NewMinuteGateway {
  final calls = <String>[];
  var create = Completer<CreateMinuteResult>();
  var upload = StreamController<UploadProgress>();
  var start = Completer<StartTranscriptionResult>();
  var progress = StreamController<MinuteProgress>();
  Object? cancelTranscriptionError;
  int maxSizeBytes = 300 * 1024 * 1024;

  CreateMinuteResult target(String id) =>
      CreateMinuteResult(minuteId: id, uploadPath: 'users/u/minutes/$id/source/a.m4a', contentType: 'audio/mp4', maxSizeBytes: maxSizeBytes);

  @override
  Future<CreateMinuteResult> createMinute({required SourceType sourceType, required String fileName, required int sizeBytes, required String contentType}) {
    calls.add('create:$fileName:$sizeBytes:${sourceType.name}');
    return create.future;
  }

  @override
  Stream<UploadProgress> upload({required File file, required CreateMinuteResult target}) {
    calls.add('upload:${target.minuteId}');
    return upload.stream;
  }

  @override
  Stream<UploadProgress> uploadParts({required List<File> parts, required CreateMinuteResult target}) {
    calls.add('uploadParts:${target.minuteId}:${parts.length}');
    return upload.stream;
  }

  @override
  Future<void> cancelUpload() async {
    calls.add('cancelUpload');
    if (!upload.isClosed) upload.addError(StateError('cancelled'));
  }

  @override
  Future<StartTranscriptionResult> start({required String minuteId, required TranscriptionOptions options, required String requestId, int? partCount}) {
    calls.add('start:$minuteId:$requestId${partCount == null ? '' : ':parts=$partCount'}');
    return start.future;
  }

  @override
  Future<void> cancelTranscription(String minuteId) async {
    calls.add('cancelTranscription:$minuteId');
    if (cancelTranscriptionError != null) throw cancelTranscriptionError!;
  }

  @override
  Future<void> deleteMinute(String minuteId) async => calls.add('delete:$minuteId');

  @override
  Stream<MinuteProgress> watchProgress(String minuteId) {
    calls.add('watch:$minuteId');
    return progress.stream;
  }

  void emit(String id, MinuteStatus s, {MinuteFailure? failure, String title = 'T'}) =>
      progress.add(MinuteProgress(id: id, status: s, failure: failure, title: title));
}

final req = NewMinuteRequest(
  file: File('/tmp/a.m4a'),
  fileName: 'a.m4a',
  sizeBytes: 1000,
  contentType: 'audio/mp4',
  options: const TranscriptionOptions(summaryLanguage: 'en'),
);

class Harness {
  Harness() {
    container = ProviderContainer.test(overrides: [newMinuteGatewayProvider.overrideWithValue(gw)]);
    // autoDispose: keep it alive and record every state.
    container.listen(newMinuteFlowProvider(req), (_, next) => states.add(next), fireImmediately: true);
  }
  final gw = FakeGateway();
  late final ProviderContainer container;
  final states = <NewMinuteState>[];

  NewMinuteState get state => container.read(newMinuteFlowProvider(req));
  NewMinuteFlow get flow => container.read(newMinuteFlowProvider(req).notifier);
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Drives the flow to the point where the worker is running.
Future<Harness> queued() async {
  final h = Harness();
  await settle();
  h.gw.create.complete(h.gw.target('m1'));
  await settle();
  h.gw.upload.add(const UploadProgress(bytesTransferred: 1000, totalBytes: 1000));
  await h.gw.upload.close();
  await settle();
  h.gw.start.complete(const StartTranscriptionResult(minuteId: 'm1', status: MinuteStatus.queued, duplicate: false));
  await settle();
  return h;
}

void main() {
  test('happy path walks creating → uploading → starting → processing → ready', () async {
    final h = await queued();
    expect(h.state, isA<NewMinuteProcessing>());
    h.gw.emit('m1', MinuteStatus.transcribing);
    await settle();
    expect((h.state as NewMinuteProcessing).status, MinuteStatus.transcribing);
    h.gw.emit('m1', MinuteStatus.summarizing);
    h.gw.emit('m1', MinuteStatus.ready, title: 'Standup');
    await settle();
    final ready = h.state as NewMinuteReady;
    expect(ready.minuteId, 'm1');
    expect(ready.title, 'Standup');
    expect(h.states.map((s) => s.runtimeType).toList(), [
      NewMinuteCreating,
      NewMinuteUploading, // 0/0 placeholder
      NewMinuteUploading, // real progress
      NewMinuteStarting,
      NewMinuteProcessing, // queued
      NewMinuteProcessing, // transcribing
      NewMinuteProcessing, // summarizing
      NewMinuteReady,
    ]);
    expect(h.gw.calls.where((c) => c.startsWith('start:')).length, 1);
    expect(h.gw.calls, isNot(contains(startsWith('delete:'))));
  });

  test('upload progress is forwarded as a fraction', () async {
    final h = Harness();
    await settle();
    h.gw.create.complete(h.gw.target('m1'));
    await settle();
    h.gw.upload.add(const UploadProgress(bytesTransferred: 250, totalBytes: 1000));
    await settle();
    expect((h.state as NewMinuteUploading).progress.fraction, 0.25);
  });

  test('file larger than the advertised limit fails locally and deletes the shell minute', () async {
    final h = Harness();
    await settle();
    h.gw.create.complete(CreateMinuteResult(minuteId: 'm1', uploadPath: 'p', contentType: 'audio/mp4', maxSizeBytes: 500));
    await settle();
    final f = h.state as NewMinuteFailed;
    expect(f.error, isA<FileTooLargeFailure>());
    expect(f.retryable, isFalse);
    expect(h.gw.calls, contains('delete:m1'));
    expect(h.gw.calls, isNot(contains(startsWith('upload:'))));
  });

  test('createMinute failure maps retryable from ApiFailure', () async {
    final h = Harness();
    await settle();
    h.gw.create.completeError(const TransientFailure('unavailable'));
    await settle();
    final f = h.state as NewMinuteFailed;
    expect(f.phase, NewMinutePhase.creating);
    expect(f.retryable, isTrue);
    expect(f.minuteId, isNull);

    // retry starts over with a fresh createMinute
    h.gw.create = Completer();
    await h.flow.retry();
    await settle();
    expect(h.state, isA<NewMinuteCreating>());
    expect(h.gw.calls.where((c) => c.startsWith('create:')).length, 2);
  });

  test('out of credits at start is final, exposes resetAt, and no second start on retry', () async {
    final h = Harness();
    await settle();
    h.gw.create.complete(h.gw.target('m1'));
    await settle();
    await h.gw.upload.close();
    await settle();
    final reset = DateTime.utc(2026, 9, 24);
    h.gw.start.completeError(QuotaFailure('no credits', reset));
    await settle();
    final f = h.state as NewMinuteFailed;
    expect(f.isOutOfCredits, isTrue);
    expect(f.creditsResetAt, reset);
    expect(f.retryable, isFalse);
    await h.flow.retry();
    expect(h.gw.calls.where((c) => c.startsWith('start:')).length, 1);
  });

  test('transient start failure retries with the SAME requestId (idempotent charge)', () async {
    final h = Harness();
    await settle();
    h.gw.create.complete(h.gw.target('m1'));
    await settle();
    await h.gw.upload.close();
    await settle();
    h.gw.start.completeError(const TransientFailure('deadline'));
    await settle();
    expect((h.state as NewMinuteFailed).retryable, isTrue);

    h.gw.start = Completer();
    await h.flow.retry();
    await settle();
    final starts = h.gw.calls.where((c) => c.startsWith('start:')).toList();
    expect(starts.length, 2);
    expect(starts[0], starts[1], reason: 'same minuteId and requestId');
  });

  test('upload error is retryable and re-uses the same upload target (no new minute)', () async {
    final h = Harness();
    await settle();
    h.gw.create.complete(h.gw.target('m1'));
    await settle();
    h.gw.upload.addError(Exception('network'));
    await settle();
    final f = h.state as NewMinuteFailed;
    expect(f.phase, NewMinutePhase.uploading);
    expect(f.retryable, isTrue);
    expect(f.minuteId, 'm1');

    h.gw.upload = StreamController();
    await h.flow.retry();
    await settle();
    expect(h.state, isA<NewMinuteUploading>());
    expect(h.gw.calls.where((c) => c.startsWith('create:')).length, 1);
    expect(h.gw.calls.where((c) => c == 'upload:m1').length, 2);
  });

  test('server failure during processing is final and carries the server code', () async {
    final h = await queued();
    h.gw.emit('m1', MinuteStatus.failed, failure: const MinuteFailure(code: 'stt_unavailable', message: 'x'));
    await settle();
    final f = h.state as NewMinuteFailed;
    expect(f.phase, NewMinutePhase.processing);
    expect(f.retryable, isFalse);
    expect(f.serverFailure?.code, 'stt_unavailable');
  });

  test('losing the Firestore listener is retryable and re-subscribes', () async {
    final h = await queued();
    h.gw.progress.addError(Exception('listener dropped'));
    await settle();
    expect((h.state as NewMinuteFailed).retryable, isTrue);
    h.gw.progress = StreamController();
    await h.flow.retry();
    await settle();
    expect(h.state, isA<NewMinuteProcessing>());
    expect(h.gw.calls.where((c) => c == 'watch:m1').length, 2);
  });

  group('cancel', () {
    test('during upload: aborts, deletes the shell minute once, ends cancelled', () async {
      final h = Harness();
      await settle();
      h.gw.create.complete(h.gw.target('m1'));
      await settle();
      await h.flow.cancel();
      await settle();
      expect(h.state, isA<NewMinuteCancelled>());
      expect(h.gw.calls, contains('cancelUpload'));
      expect(h.gw.calls.where((c) => c == 'delete:m1').length, 1);
      expect(h.gw.calls, isNot(contains(startsWith('start:'))));
    });

    test('while createMinute is in flight: deletes as soon as it returns', () async {
      final h = Harness();
      await settle();
      await h.flow.cancel();
      h.gw.create.complete(h.gw.target('m1'));
      await settle();
      expect(h.state, isA<NewMinuteCancelled>());
      expect(h.gw.calls, contains('delete:m1'));
      expect(h.gw.calls, isNot(contains('upload:m1')));
    });

    test('while start is in flight: cancels the job after it is queued (server refunds)', () async {
      final h = Harness();
      await settle();
      h.gw.create.complete(h.gw.target('m1'));
      await settle();
      await h.gw.upload.close();
      await settle();
      expect(h.state, isA<NewMinuteStarting>());
      await h.flow.cancel();
      h.gw.start.complete(const StartTranscriptionResult(minuteId: 'm1', status: MinuteStatus.queued, duplicate: false));
      await settle();
      expect(h.gw.calls, contains('cancelTranscription:m1'));
      expect(h.gw.calls, isNot(contains('delete:m1')), reason: 'queued jobs are cancelled, not deleted');
      h.gw.emit('m1', MinuteStatus.cancelled);
      await settle();
      expect(h.state, isA<NewMinuteCancelled>());
    });

    test('while processing: calls cancelTranscription and waits for the listener', () async {
      final h = await queued();
      await h.flow.cancel();
      expect(h.state, isA<NewMinuteProcessing>(), reason: 'not cancelled until the server says so');
      h.gw.emit('m1', MinuteStatus.cancelled);
      await settle();
      expect(h.state, isA<NewMinuteCancelled>());
    });

    test('server says already terminal: swallowed, listener decides', () async {
      final h = await queued();
      h.gw.cancelTranscriptionError = const PreconditionFailure('done', 'terminal', null);
      await h.flow.cancel();
      h.gw.emit('m1', MinuteStatus.ready, title: 'Late');
      await settle();
      expect(h.state, isA<NewMinuteReady>());
    });

    test('after a terminal state is a no-op', () async {
      final h = await queued();
      h.gw.emit('m1', MinuteStatus.ready);
      await settle();
      h.gw.calls.clear();
      await h.flow.cancel();
      expect(h.gw.calls, isEmpty);
    });
  });

  test('disposing the provider cancels the progress subscription', () async {
    final h = await queued();
    expect(h.gw.progress.hasListener, isTrue);
    h.container.dispose();
    await settle();
    expect(h.gw.progress.hasListener, isFalse);
  });

  test('S11-09 a chunked recording uploads every part and starts with partCount', () async {
    final gw = FakeGateway();
    final container = ProviderContainer.test(overrides: [newMinuteGatewayProvider.overrideWithValue(gw)]);
    final chunked = NewMinuteRequest(file: File('/tmp/p0.m4a'), parts: [File('/tmp/p0.m4a'), File('/tmp/p1.m4a')], fileName: 'p0.m4a', sizeBytes: 10, contentType: 'audio/mp4', options: req.options);
    expect(chunked.isChunked, isTrue);
    container.listen(newMinuteFlowProvider(chunked), (_, __) {});
    await settle();
    gw.create.complete(gw.target('m9'));
    await settle();
    expect(gw.calls, contains('uploadParts:m9:2'));
    gw.upload.add(const UploadProgress(bytesTransferred: 10, totalBytes: 10));
    await gw.upload.close();
    await settle();
    expect(gw.calls.last, startsWith('start:m9:'));
    expect(gw.calls.last, endsWith(':parts=2'));
  });
}
