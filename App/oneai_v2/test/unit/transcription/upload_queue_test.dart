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
import 'package:one_ai/features/transcription/upload_queue.dart';

class FakeGateway implements NewMinuteGateway {
  final calls = <String>[];
  var create = Completer<CreateMinuteResult>();
  var upload = StreamController<UploadProgress>();
  var start = Completer<StartTranscriptionResult>();
  var progress = StreamController<MinuteProgress>();
  CreateMinuteResult target(String id) => CreateMinuteResult(minuteId: id, uploadPath: 'p', contentType: 'audio/mp4', maxSizeBytes: 1 << 30);
  @override
  Future<CreateMinuteResult> createMinute({required SourceType sourceType, required String fileName, required int sizeBytes, required String contentType}) {
    calls.add('create');
    return create.future;
  }
  @override
  Stream<UploadProgress> upload({required File file, required CreateMinuteResult target}) { calls.add('upload'); return upload.stream; }
  @override
  Future<void> cancelUpload() async {}
  @override
  Future<StartTranscriptionResult> start({required String minuteId, required TranscriptionOptions options, required String requestId}) { calls.add('start'); return start.future; }
  @override
  Future<void> cancelTranscription(String minuteId) async {}
  @override
  Future<void> deleteMinute(String minuteId) async {}
  @override
  Stream<MinuteProgress> watchProgress(String minuteId) { calls.add('watch'); return progress.stream; }
}

class MemoryStore implements UploadQueueStore {
  List<NewMinuteRequest> saved = [];
  @override
  Future<List<NewMinuteRequest>> load() async => saved;
  @override
  Future<void> save(List<NewMinuteRequest> q) async => saved = List.of(q);
}

final req = NewMinuteRequest(
  file: File('${Directory.systemTemp.path}/oneai_q.m4a'),
  fileName: 'q.m4a',
  sizeBytes: 10,
  contentType: 'audio/mp4',
  options: const TranscriptionOptions(summaryLanguage: 'English', keywords: ['a'], template: MinuteTemplate.standup),
);

Future<void> settle() async { for (var i = 0; i < 10; i++) { await Future<void>.delayed(Duration.zero); } }

class Harness {
  Harness({bool online = true}) {
    onlineCtl.add(online);
    container = ProviderContainer.test(overrides: [
      newMinuteGatewayProvider.overrideWithValue(gw),
      uploadQueueStoreProvider.overrideWithValue(store),
      onlineProvider.overrideWith((_) => onlineCtl.stream),
    ]);
    container.listen(uploadQueueProvider, (_, __) {});
    container.listen(onlineProvider, (_, __) {});
  }
  final gw = FakeGateway();
  final store = MemoryStore();
  final onlineCtl = StreamController<bool>.broadcast();
  late final ProviderContainer container;
  UploadQueue get queue => container.read(uploadQueueProvider.notifier);
  List<NewMinuteRequest> get q => container.read(uploadQueueProvider);
}

void main() {
  setUpAll(() => req.file.writeAsStringSync('x'));

  test('request JSON round-trips including template', () {
    final back = requestFromJson(Map<String, dynamic>.from(requestToJson(req)))!;
    expect(back, req);
    expect(back.options.template, MinuteTemplate.standup);
    expect(back.options.keywords, ['a']);
    expect(requestFromJson({'nope': 1}), isNull);
  });

  test('enqueue keeps the flow alive, persists, and leaves once the server owns the job', () async {
    final h = Harness();
    await settle();
    h.queue.enqueue(req);
    await settle();
    expect(h.q, [req]);
    expect(h.store.saved, [req]);
    expect(h.gw.calls, ['create']);
    h.gw.create.complete(h.gw.target('m1'));
    await settle();
    h.gw.upload.close();
    await settle();
    h.gw.start.complete(const StartTranscriptionResult(minuteId: 'm1', status: MinuteStatus.queued, duplicate: false));
    await settle();
    expect(h.gw.calls, ['create', 'upload', 'start', 'watch']);
    expect(h.q, isEmpty, reason: 'processing = server owns it');
    expect(h.store.saved, isEmpty);
  });

  test('offline failure waits; the online edge retries create', () async {
    final h = Harness(online: false);
    await settle();
    h.queue.enqueue(req);
    await settle();
    h.gw.create.completeError(const NetworkFailure('offline'));
    await settle();
    expect(h.container.read(newMinuteFlowProvider(req)), isA<NewMinuteFailed>());
    expect(h.queue.waiting, [req]);
    h.gw.create = Completer<CreateMinuteResult>();
    h.onlineCtl.add(true);
    await settle();
    expect(h.gw.calls, ['create', 'create']);
  });

  test('a non-retryable failure drops the entry', () async {
    final h = Harness();
    await settle();
    h.queue.enqueue(req);
    await settle();
    h.gw.create.completeError(const QuotaFailure('no credits', null));
    await settle();
    expect(h.q, isEmpty);
  });

  test('restore re-enqueues saved requests whose file still exists', () async {
    final store = MemoryStore()..saved = [req, req.copyWithPath('${Directory.systemTemp.path}/missing.m4a')];
    final gw = FakeGateway();
    final ctl = StreamController<bool>.broadcast();
    final c = ProviderContainer.test(overrides: [
      newMinuteGatewayProvider.overrideWithValue(gw),
      uploadQueueStoreProvider.overrideWithValue(store),
      onlineProvider.overrideWith((_) => ctl.stream),
    ]);
    c.listen(uploadQueueProvider, (_, __) {});
    await settle();
    expect(c.read(uploadQueueProvider), [req]);
    expect(gw.calls, ['create']);
  });
}

extension on NewMinuteRequest {
  NewMinuteRequest copyWithPath(String p) => NewMinuteRequest(file: File(p), fileName: fileName, sizeBytes: sizeBytes, contentType: contentType, options: options);
}
