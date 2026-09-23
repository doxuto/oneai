import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:one_ai/features/transcription/recording_service.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RecordingPhase { initial, recording, paused }

/// Chunk length. Every chunk is a complete, playable m4a the moment it is
/// closed, so a crash or a killed process loses at most this much (S11-09).
const recordingChunk = Duration(minutes: 5);

class RecordingState {
  const RecordingState({
    this.phase = RecordingPhase.initial,
    this.seconds = 0,
    this.path,
    this.closedParts = const [],
    this.permissionDenied = false,
    this.amplitude = 0,
    this.interrupted = false,
    this.resumedAfterInterruption = false,
  });
  final RecordingPhase phase;
  final int seconds;
  /// The chunk being written right now.
  final String? path;
  /// Finished chunks, in order. `parts` = these + [path].
  final List<String> closedParts;
  List<String> get parts => [...closedParts, if (path != null) path!];
  final bool permissionDenied;
  /// 0..1 from the mic, for the wave rings.
  final double amplitude;
  /// The OS took the mic (call, Siri, another app) — we did not press pause.
  final bool interrupted;
  /// One-shot flag the screen turns into a snack, then clears.
  final bool resumedAfterInterruption;

  RecordingState copyWith({RecordingPhase? phase, int? seconds, String? path, List<String>? closedParts, bool? permissionDenied, double? amplitude, bool? interrupted, bool? resumedAfterInterruption}) =>
      RecordingState(
        phase: phase ?? this.phase,
        seconds: seconds ?? this.seconds,
        path: path ?? this.path,
        closedParts: closedParts ?? this.closedParts,
        permissionDenied: permissionDenied ?? this.permissionDenied,
        amplitude: amplitude ?? this.amplitude,
        interrupted: interrupted ?? this.interrupted,
        resumedAfterInterruption: resumedAfterInterruption ?? this.resumedAfterInterruption,
      );
}

final recorderProvider = NotifierProvider.autoDispose<RecorderController, RecordingState>(RecorderController.new);

/// A recording the app did not get to finish (crash, force-quit, battery).
/// Written when recording starts, refreshed every 15 s, cleared on finish or
/// discard; Home offers to recover it on the next launch (A7-02 / S11-09).
class UnfinishedRecording {
  const UnfinishedRecording({required this.paths, required this.startedAt, required this.seconds});
  /// Chunks in order; the last one may be truncated (it was open at the crash).
  final List<String> paths;
  final DateTime startedAt;
  final int seconds;

  String get path => paths.last;

  static const key = 'UNFINISHED_RECORDING_V2';

  Map<String, Object?> toJson() => {'paths': paths, 'startedAt': startedAt.toIso8601String(), 'seconds': seconds};
  static UnfinishedRecording? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = j['startedAt'];
    final raw = j['paths'] ?? [if (j['path'] is String) j['path']];
    if (raw is! List || raw.isEmpty || at is! String) return null;
    return UnfinishedRecording(paths: raw.whereType<String>().toList(), startedAt: DateTime.tryParse(at) ?? DateTime.now(), seconds: (j['seconds'] as num?)?.toInt() ?? 0);
  }

  /// Chunks that are actually usable: present and not just a header. The
  /// open chunk of a crashed recording is often unplayable (no moov atom) —
  /// dropping it is what makes chunking worth it.
  List<File> usableFiles() => [
        for (final p in paths)
          if (File(p).existsSync() && File(p).lengthSync() >= 8 * 1024) File(p),
      ];

  static Future<UnfinishedRecording?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return null;
      final r = fromJson(jsonDecode(raw));
      if (r == null) return null;
      // Anything under ~2 s is noise, and no usable chunk is unrecoverable.
      if (r.usableFiles().isEmpty || r.seconds < 2) {
        await clear();
        return null;
      }
      return r;
    } on Object catch (_) {
      return null;
    }
  }

  static Future<void> save(UnfinishedRecording r) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, jsonEncode(r.toJson()));
    } on Object catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(key);
    } on Object catch (_) {}
  }
}

/// The `record` package behind a notifier so the screen is a pure view.
/// AAC-LC m4a at 128 kbps / 44.1 kHz — the same settings v1 shipped, which
/// ElevenLabs and Gemini both accept without conversion.
///
/// Interruption-proof (A7-02): the recorder's own state stream tells us when
/// the OS paused us (incoming call, Siri, another app grabbing the mic); we
/// mark `interrupted` and resume by ourselves as soon as the app is active
/// again, instead of silently losing the rest of the meeting. A marker file
/// lets Home recover a recording after a crash.
class RecorderController extends Notifier<RecordingState> with WidgetsBindingObserver {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _tick;
  Timer? _marker;
  Timer? _chunk;
  RecordConfig? _config;
  Directory? _dir;
  StreamSubscription<Amplitude>? _amp;
  StreamSubscription<RecordState>? _rs;
  DateTime? _startedAt;
  bool _userPaused = false;

  /// Text of the Android foreground notification; the screen sets the
  /// localized strings before recording starts (the controller has no context).
  String notificationTitle = 'One AI';
  String notificationText = 'Recording';

  @override
  RecordingState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() async {
      WidgetsBinding.instance.removeObserver(this);
      _tick?.cancel();
      _marker?.cancel();
      _chunk?.cancel();
      await _amp?.cancel();
      await _rs?.cancel();
      // Leaving the screen mid-recording discards it (v1 behaviour after the
      // exit warning); a finished recording has already been stopped.
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        await _recorder.cancel();
        _deleteFiles(state.closedParts);
        await UnfinishedRecording.clear();
      }
      await RecordingService.stop();
      await _recorder.dispose();
    });
    return const RecordingState();
  }

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(permissionDenied: true);
      return;
    }
    _dir = await getApplicationDocumentsDirectory();
    _config = const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 128000,
      sampleRate: 44100,
      // iOS: keep the session alive under the lock screen and mix politely
      // with system sounds; Android: raw voice source so the OS does not
      // apply call-style processing.
      iosConfig: IosRecordConfig(categoryOptions: [IosAudioCategoryOption.allowBluetooth, IosAudioCategoryOption.defaultToSpeaker]),
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
    );
    await RecordingService.start(title: notificationTitle, text: notificationText);
    final path = _nextPath();
    await _recorder.start(_config!, path: path);
    _startedAt = DateTime.now();
    _userPaused = false;
    state = state.copyWith(phase: RecordingPhase.recording, path: path, closedParts: const [], permissionDenied: false, interrupted: false);
    _startTick();
    _startChunkTimer();
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 200)).listen((a) {
      // dBFS (≈ -160..0) → 0..1
      final v = ((a.current + 60) / 60).clamp(0.0, 1.0);
      state = state.copyWith(amplitude: v);
    });
    _rs = _recorder.onStateChanged().listen(_onRecorderState);
    unawaited(_saveMarker());
    _marker?.cancel();
    _marker = Timer.periodic(const Duration(seconds: 15), (_) => _saveMarker());
  }

  String _nextPath() => '${_dir!.path}/minutes_ai_${DateTime.now().millisecondsSinceEpoch}_${state.closedParts.length}.m4a';

  void _startChunkTimer() {
    _chunk?.cancel();
    _chunk = Timer.periodic(recordingChunk, (_) => _rotateChunk());
  }

  /// Closes the current chunk (now a complete file) and opens the next one.
  /// The ~100 ms gap between them is inaudible in a meeting; the server
  /// joins the chunks before transcription (`partCount`).
  bool _rotating = false;

  Future<void> _rotateChunk() async {
    if (state.phase != RecordingPhase.recording || _config == null || _rotating) return;
    _rotating = true;
    try {
      final closed = await _recorder.stop();
      if (closed == null) return;
      final next = _nextPath();
      await _recorder.start(_config!, path: next);
      state = state.copyWith(path: next, closedParts: [...state.closedParts, closed]);
      unawaited(_saveMarker());
    } on Object catch (e) {
      dev.log('chunk rotation failed', name: 'recorder', error: e);
    } finally {
      _rotating = false;
    }
  }

  /// The plugin reports pause/stop it did not get from us → interruption.
  void _onRecorderState(RecordState s) {
    if (state.phase != RecordingPhase.recording) return;
    if (s == RecordState.pause || s == RecordState.stop) {
      if (_userPaused || _rotating) return;
      dev.log('recording interrupted by the system', name: 'recorder');
      _tick?.cancel();
      state = state.copyWith(phase: RecordingPhase.paused, amplitude: 0, interrupted: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Back in the foreground after a call: pick up where we were.
    if (s == AppLifecycleState.resumed && state.interrupted) unawaited(_resumeAfterInterruption());
  }

  Future<void> _resumeAfterInterruption() async {
    try {
      if (await _recorder.isPaused()) {
        await _recorder.resume();
        state = state.copyWith(phase: RecordingPhase.recording, interrupted: false, resumedAfterInterruption: true);
        _startTick();
      } else if (_config != null) {
        // The OS stopped us outright (audio session lost). The chunk so far
        // is closed and safe; carry on in a fresh chunk instead of giving up.
        final closed = state.path;
        final next = _nextPath();
        await _recorder.start(_config!, path: next);
        state = state.copyWith(
          phase: RecordingPhase.recording,
          path: next,
          closedParts: [...state.closedParts, if (closed != null && File(closed).existsSync()) closed],
          interrupted: false,
          resumedAfterInterruption: true,
        );
        _startTick();
        _startChunkTimer();
        unawaited(_saveMarker());
      }
    } on Object catch (e) {
      dev.log('resume after interruption failed', name: 'recorder', error: e);
    }
  }

  void ackResumed() => state = state.copyWith(resumedAfterInterruption: false);

  Future<void> pause() async {
    _userPaused = true;
    await _recorder.pause();
    _tick?.cancel();
    _chunk?.cancel();
    state = state.copyWith(phase: RecordingPhase.paused, amplitude: 0);
  }

  Future<void> resume() async {
    _userPaused = false;
    await _recorder.resume();
    state = state.copyWith(phase: RecordingPhase.recording, interrupted: false);
    _startTick();
    _startChunkTimer();
  }

  Future<void> toggle() => switch (state.phase) {
        RecordingPhase.initial => start(),
        RecordingPhase.recording => pause(),
        RecordingPhase.paused => resume(),
      };

  /// Finalises the recording and returns its chunks in order (one file for a
  /// short recording). Only valid when paused (v1 shows the Transcribe button
  /// only in that state).
  Future<List<File>?> finish() async {
    _tick?.cancel();
    _marker?.cancel();
    _chunk?.cancel();
    await _amp?.cancel();
    await _rs?.cancel();
    final path = await _recorder.stop();
    await RecordingService.stop();
    await UnfinishedRecording.clear();
    final parts = [...state.closedParts, if (path != null) path];
    if (parts.isEmpty) return null;
    state = state.copyWith(phase: RecordingPhase.initial);
    return [for (final p in parts) File(p)];
  }

  /// Discards everything.
  Future<void> discard() async {
    _tick?.cancel();
    _marker?.cancel();
    await _amp?.cancel();
    await _rs?.cancel();
    _chunk?.cancel();
    await _recorder.cancel();
    await RecordingService.stop();
    _deleteFiles(state.closedParts);
    await UnfinishedRecording.clear();
    state = const RecordingState();
  }

  static void _deleteFiles(List<String> paths) {
    for (final p in paths) {
      try {
        File(p).deleteSync();
      } on Object catch (_) {}
    }
  }

  Future<void> _saveMarker() async {
    final at = _startedAt;
    if (state.parts.isEmpty || at == null) return;
    await UnfinishedRecording.save(UnfinishedRecording(paths: state.parts, startedAt: at, seconds: state.seconds));
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => state = state.copyWith(seconds: state.seconds + 1));
  }
}
