import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum RecordingPhase { initial, recording, paused }

class RecordingState {
  const RecordingState({
    this.phase = RecordingPhase.initial,
    this.seconds = 0,
    this.path,
    this.permissionDenied = false,
    this.amplitude = 0,
    this.interrupted = false,
    this.resumedAfterInterruption = false,
  });
  final RecordingPhase phase;
  final int seconds;
  final String? path;
  final bool permissionDenied;
  /// 0..1 from the mic, for the wave rings.
  final double amplitude;
  /// The OS took the mic (call, Siri, another app) — we did not press pause.
  final bool interrupted;
  /// One-shot flag the screen turns into a snack, then clears.
  final bool resumedAfterInterruption;

  RecordingState copyWith({RecordingPhase? phase, int? seconds, String? path, bool? permissionDenied, double? amplitude, bool? interrupted, bool? resumedAfterInterruption}) =>
      RecordingState(
        phase: phase ?? this.phase,
        seconds: seconds ?? this.seconds,
        path: path ?? this.path,
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
  const UnfinishedRecording({required this.path, required this.startedAt, required this.seconds});
  final String path;
  final DateTime startedAt;
  final int seconds;

  static const key = 'UNFINISHED_RECORDING_V2';

  Map<String, Object?> toJson() => {'path': path, 'startedAt': startedAt.toIso8601String(), 'seconds': seconds};
  static UnfinishedRecording? fromJson(Object? j) {
    if (j is! Map) return null;
    final path = j['path'];
    final at = j['startedAt'];
    if (path is! String || at is! String) return null;
    return UnfinishedRecording(path: path, startedAt: DateTime.tryParse(at) ?? DateTime.now(), seconds: (j['seconds'] as num?)?.toInt() ?? 0);
  }

  static Future<UnfinishedRecording?> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(key);
      if (raw == null) return null;
      final r = fromJson(jsonDecode(raw));
      if (r == null) return null;
      final f = File(r.path);
      // Anything under ~2 s is noise, and an empty file is unrecoverable.
      if (!f.existsSync() || f.lengthSync() < 8 * 1024 || r.seconds < 2) {
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
  StreamSubscription<Amplitude>? _amp;
  StreamSubscription<RecordState>? _rs;
  DateTime? _startedAt;
  bool _userPaused = false;

  @override
  RecordingState build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() async {
      WidgetsBinding.instance.removeObserver(this);
      _tick?.cancel();
      _marker?.cancel();
      await _amp?.cancel();
      await _rs?.cancel();
      // Leaving the screen mid-recording discards it (v1 behaviour after the
      // exit warning); a finished recording has already been stopped.
      if (await _recorder.isRecording() || await _recorder.isPaused()) {
        await _recorder.cancel();
        await UnfinishedRecording.clear();
      }
      await _recorder.dispose();
    });
    return const RecordingState();
  }

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      state = state.copyWith(permissionDenied: true);
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/minutes_ai_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        // iOS: keep the session alive under the lock screen and mix politely
        // with system sounds; Android: raw voice source so the OS does not
        // apply call-style processing.
        iosConfig: IosRecordConfig(categoryOptions: [IosAudioCategoryOption.allowBluetooth, IosAudioCategoryOption.defaultToSpeaker]),
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.mic),
      ),
      path: path,
    );
    _startedAt = DateTime.now();
    _userPaused = false;
    state = state.copyWith(phase: RecordingPhase.recording, path: path, permissionDenied: false, interrupted: false);
    _startTick();
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

  /// The plugin reports pause/stop it did not get from us → interruption.
  void _onRecorderState(RecordState s) {
    if (state.phase != RecordingPhase.recording) return;
    if (s == RecordState.pause || s == RecordState.stop) {
      if (_userPaused) return;
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
      } else {
        // The OS stopped us outright; keep what we have, let the user decide.
        state = state.copyWith(interrupted: false);
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
    state = state.copyWith(phase: RecordingPhase.paused, amplitude: 0);
  }

  Future<void> resume() async {
    _userPaused = false;
    await _recorder.resume();
    state = state.copyWith(phase: RecordingPhase.recording, interrupted: false);
    _startTick();
  }

  Future<void> toggle() => switch (state.phase) {
        RecordingPhase.initial => start(),
        RecordingPhase.recording => pause(),
        RecordingPhase.paused => resume(),
      };

  /// Finalises the file and returns it. Only valid when paused (v1 shows the
  /// Transcribe button only in that state).
  Future<File?> finish() async {
    _tick?.cancel();
    _marker?.cancel();
    await _amp?.cancel();
    await _rs?.cancel();
    final path = await _recorder.stop();
    await UnfinishedRecording.clear();
    if (path == null) return null;
    state = state.copyWith(phase: RecordingPhase.initial);
    return File(path);
  }

  /// Discards everything.
  Future<void> discard() async {
    _tick?.cancel();
    _marker?.cancel();
    await _amp?.cancel();
    await _rs?.cancel();
    await _recorder.cancel();
    await UnfinishedRecording.clear();
    state = const RecordingState();
  }

  Future<void> _saveMarker() async {
    final p = state.path;
    final at = _startedAt;
    if (p == null || at == null) return;
    await UnfinishedRecording.save(UnfinishedRecording(path: p, startedAt: at, seconds: state.seconds));
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => state = state.copyWith(seconds: state.seconds + 1));
  }
}
