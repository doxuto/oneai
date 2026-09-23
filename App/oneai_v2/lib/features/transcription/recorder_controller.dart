import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum RecordingPhase { initial, recording, paused }

class RecordingState {
  const RecordingState({this.phase = RecordingPhase.initial, this.seconds = 0, this.path, this.permissionDenied = false, this.amplitude = 0});
  final RecordingPhase phase;
  final int seconds;
  final String? path;
  final bool permissionDenied;
  /// 0..1 from the mic, for the wave rings.
  final double amplitude;

  RecordingState copyWith({RecordingPhase? phase, int? seconds, String? path, bool? permissionDenied, double? amplitude}) => RecordingState(
        phase: phase ?? this.phase,
        seconds: seconds ?? this.seconds,
        path: path ?? this.path,
        permissionDenied: permissionDenied ?? this.permissionDenied,
        amplitude: amplitude ?? this.amplitude,
      );
}

final recorderProvider = NotifierProvider.autoDispose<RecorderController, RecordingState>(RecorderController.new);

/// The `record` package behind a notifier so the screen is a pure view.
/// AAC-LC m4a at 128 kbps / 44.1 kHz — the same settings v1 shipped, which
/// ElevenLabs and Gemini both accept without conversion.
class RecorderController extends Notifier<RecordingState> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _tick;
  StreamSubscription<Amplitude>? _amp;

  @override
  RecordingState build() {
    ref.onDispose(() async {
      _tick?.cancel();
      await _amp?.cancel();
      // Leaving the screen mid-recording discards it (v1 behaviour after the
      // exit warning); a finished recording has already been stopped.
      if (await _recorder.isRecording() || await _recorder.isPaused()) await _recorder.cancel();
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
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000, sampleRate: 44100), path: path);
    state = state.copyWith(phase: RecordingPhase.recording, path: path, permissionDenied: false);
    _startTick();
    _amp = _recorder.onAmplitudeChanged(const Duration(milliseconds: 200)).listen((a) {
      // dBFS (≈ -160..0) → 0..1
      final v = ((a.current + 60) / 60).clamp(0.0, 1.0);
      state = state.copyWith(amplitude: v);
    });
  }

  Future<void> pause() async {
    await _recorder.pause();
    _tick?.cancel();
    state = state.copyWith(phase: RecordingPhase.paused, amplitude: 0);
  }

  Future<void> resume() async {
    await _recorder.resume();
    state = state.copyWith(phase: RecordingPhase.recording);
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
    await _amp?.cancel();
    final path = await _recorder.stop();
    if (path == null) return null;
    state = state.copyWith(phase: RecordingPhase.initial);
    return File(path);
  }

  /// Discards everything.
  Future<void> discard() async {
    _tick?.cancel();
    await _amp?.cancel();
    await _recorder.cancel();
    state = const RecordingState();
  }

  void _startTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => state = state.copyWith(seconds: state.seconds + 1));
  }
}
