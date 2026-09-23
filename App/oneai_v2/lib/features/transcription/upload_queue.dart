import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/transcribe_models.dart';
import 'package:one_ai/features/transcription/new_minute_flow.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// S11-07 — offline recording. A new note's request is enqueued the moment
/// the processing screen opens; the queue keeps its [NewMinuteFlow] alive
/// after the screen is left, retries create/upload/start when the network
/// comes back, and survives a restart (the recording file stays on disk).
///
/// An entry leaves the queue once the server owns the job (processing) or
/// the flow ends. Resuming after a restart re-runs create → upload → start
/// with a fresh minute; a half-uploaded minute from the previous run is an
/// orphan the daily sweep removes. Never after `start` — that would charge
/// twice — which is why processing is the exit point.

// ---- Persistence ----

Map<String, Object?> requestToJson(NewMinuteRequest r) => {
      'path': r.file.path,
      'parts': [for (final f in r.parts) f.path],
      'fileName': r.fileName,
      'sizeBytes': r.sizeBytes,
      'contentType': r.contentType,
      'options': {
        'summaryLanguage': r.options.summaryLanguage,
        'audioLanguage': r.options.audioLanguage,
        'keywords': r.options.keywords,
        'description': r.options.description,
        'template': r.options.template.wire,
        'durationSeconds': r.options.durationSeconds,
      },
    };

NewMinuteRequest? requestFromJson(Map<String, dynamic> j) {
  final path = j['path'];
  final o = j['options'];
  if (path is! String || o is! Map) return null;
  final opt = Map<String, dynamic>.from(o);
  return NewMinuteRequest(
    file: File(path),
    parts: [for (final p in (j['parts'] as List?)?.whereType<String>() ?? const <String>[]) File(p)],
    fileName: j['fileName'] as String? ?? path.split('/').last,
    sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
    contentType: j['contentType'] as String? ?? 'audio/mp4',
    options: TranscriptionOptions(
      summaryLanguage: opt['summaryLanguage'] as String? ?? 'English',
      audioLanguage: opt['audioLanguage'] as String? ?? 'auto',
      keywords: (opt['keywords'] as List?)?.whereType<String>().toList() ?? const [],
      description: opt['description'] as String?,
      template: MinuteTemplate.fromWire(opt['template'] as String?),
      durationSeconds: (opt['durationSeconds'] as num?)?.toDouble(),
    ),
  );
}

class UploadQueueStore {
  static const key = 'UPLOAD_QUEUE_V2';

  Future<List<NewMinuteRequest>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map)
            if (requestFromJson(Map<String, dynamic>.from(e)) case final r?) r,
      ];
    } on Object catch (_) {
      return const [];
    }
  }

  Future<void> save(List<NewMinuteRequest> q) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode([for (final r in q) requestToJson(r)]));
    } on Object catch (_) {}
  }
}

// ---- Connectivity ----

/// True when any interface is up. Overridable in tests.
final onlineProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool up(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  yield up(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(up);
});

// ---- Queue ----

final uploadQueueStoreProvider = Provider<UploadQueueStore>((_) => UploadQueueStore());

final uploadQueueProvider = NotifierProvider<UploadQueue, List<NewMinuteRequest>>(UploadQueue.new);

class UploadQueue extends Notifier<List<NewMinuteRequest>> {
  final _subs = <NewMinuteRequest, ProviderSubscription<NewMinuteState>>{};
  Timer? _retryTimer;
  int _backoff = 0;

  @override
  List<NewMinuteRequest> build() {
    ref.onDispose(() {
      _retryTimer?.cancel();
      for (final s in _subs.values) s.close();
    });
    ref.listen<AsyncValue<bool>>(onlineProvider, (prev, next) {
      if ((next.valueOrNull ?? false) && !(prev?.valueOrNull ?? false)) _retryWaiting();
    });
    unawaited(_restore());
    return const [];
  }

  bool get _online => ref.read(onlineProvider).valueOrNull ?? true;

  Future<void> _restore() async {
    final saved = await ref.read(uploadQueueStoreProvider).load();
    for (final r in saved) {
      if (!r.file.existsSync()) continue; // recording gone — nothing to resume
      enqueue(r);
    }
  }

  /// Idempotent: the processing screen calls this on open; a restart calls
  /// it for every saved entry.
  void enqueue(NewMinuteRequest r) {
    if (_subs.containsKey(r)) return;
    state = [...state, r];
    unawaited(ref.read(uploadQueueStoreProvider).save(state));
    // Listening keeps the autoDispose flow alive beyond the screen.
    _subs[r] = ref.listen<NewMinuteState>(newMinuteFlowProvider(r), (_, next) => _onState(r, next), fireImmediately: true);
  }

  void remove(NewMinuteRequest r) {
    _subs.remove(r)?.close();
    if (state.contains(r)) {
      state = [for (final x in state) if (x != r) x];
      unawaited(ref.read(uploadQueueStoreProvider).save(state));
    }
  }

  /// Entries whose flow is waiting for the network (Home shows a banner).
  List<NewMinuteRequest> get waiting => [
        for (final r in state)
          if (_isWaiting(ref.read(newMinuteFlowProvider(r)))) r,
      ];

  static bool _isWaiting(NewMinuteState s) =>
      s is NewMinuteFailed && s.retryable && s.phase != NewMinutePhase.processing;

  void _onState(NewMinuteRequest r, NewMinuteState s) {
    switch (s) {
      case NewMinuteProcessing() || NewMinuteReady():
        // Server owns the job now; Home's live list shows it from here.
        remove(r);
      case NewMinuteCancelled():
        remove(r);
      case NewMinuteFailed(:final retryable, :final phase):
        if (!retryable) {
          remove(r); // quota / precondition / too large — user must act
        } else if (phase == NewMinutePhase.processing) {
          remove(r); // job accepted; only the listener dropped
        } else if (_online && s.error is! NetworkFailure) {
          _scheduleRetry(); // transient server error while online: backoff
        }
        // offline: wait for the connectivity edge
      case NewMinuteCreating() || NewMinuteUploading() || NewMinuteStarting():
        _backoff = 0;
    }
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive ?? false) return;
    final delay = Duration(seconds: [5, 15, 60, 300][_backoff.clamp(0, 3)]);
    _backoff += 1;
    _retryTimer = Timer(delay, _retryWaiting);
  }

  void _retryWaiting() {
    _retryTimer?.cancel();
    for (final r in waiting) {
      dev.log('upload queue: retrying ${r.fileName}', name: 'transcription');
      unawaited(ref.read(newMinuteFlowProvider(r).notifier).retry());
    }
  }
}
