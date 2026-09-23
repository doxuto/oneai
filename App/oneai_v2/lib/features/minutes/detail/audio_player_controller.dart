import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:one_ai/core/di/providers.dart';

enum PlayerPhase { idle, loading, ready, failed }

class PlayerState {
  const PlayerState({
    this.phase = PlayerPhase.idle,
    this.expanded = false,
    this.playing = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.error,
  });
  final PlayerPhase phase;
  /// Mini play FAB vs the full control dashboard (v1's two states).
  final bool expanded;
  final bool playing;
  final Duration position;
  final Duration duration;
  final double speed;
  final Object? error;

  double get positionSeconds => position.inMilliseconds / 1000;

  PlayerState copyWith({PlayerPhase? phase, bool? expanded, bool? playing, Duration? position, Duration? duration, double? speed, Object? error = _keep}) =>
      PlayerState(
        phase: phase ?? this.phase,
        expanded: expanded ?? this.expanded,
        playing: playing ?? this.playing,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        speed: speed ?? this.speed,
        error: identical(error, _keep) ? this.error : error,
      );
}

const Object _keep = Object();

/// One player per note. Streams straight from the Storage download URL
/// (just_audio caches); v1 downloaded the whole file first.
final audioPlayerProvider = NotifierProvider.autoDispose.family<AudioPlayerController, PlayerState, String>(AudioPlayerController.new);

class AudioPlayerController extends Notifier<PlayerState> {
  AudioPlayerController(this.minuteId);
  final String minuteId;

  static const speeds = [0.5, 1.0, 1.5, 2.0];
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<Object?>> _subs = [];

  @override
  PlayerState build() {
    ref.onDispose(() async {
      for (final s in _subs) await s.cancel();
      await _player.dispose();
    });
    _subs
      ..add(_player.positionStream.listen((p) => state = state.copyWith(position: p)))
      ..add(_player.durationStream.listen((d) => state = state.copyWith(duration: d ?? Duration.zero)))
      ..add(_player.playerStateStream.listen((s) {
        final done = s.processingState == ProcessingState.completed;
        if (done) _player.pause();
        state = state.copyWith(playing: s.playing && !done);
        if (done) unawaited(_player.seek(Duration.zero));
      }));
    return const PlayerState();
  }

  /// First tap on the mini FAB: load (if needed), expand, play.
  Future<void> open(String sourcePath) async {
    if (state.phase == PlayerPhase.idle || state.phase == PlayerPhase.failed) {
      state = state.copyWith(phase: PlayerPhase.loading, error: null);
      try {
        final url = await ref.read(transcriptionRepositoryProvider).downloadUrl(sourcePath);
        await _player.setUrl(url);
        state = state.copyWith(phase: PlayerPhase.ready);
      } on Object catch (e) {
        dev.log('audio load failed', name: 'player', error: e);
        state = state.copyWith(phase: PlayerPhase.failed, error: e);
        return;
      }
    }
    state = state.copyWith(expanded: true);
    await _player.play();
  }

  Future<void> toggle() => state.playing ? _player.pause() : _player.play();

  Future<void> seek(Duration to) => _player.seek(to < Duration.zero ? Duration.zero : (to > state.duration ? state.duration : to));
  Future<void> seekSeconds(double s) => seek(Duration(milliseconds: (s * 1000).round()));
  Future<void> seekRelative(Duration by) => seek(state.position + by);

  Future<void> cycleSpeed() async {
    final next = speeds[(speeds.indexOf(state.speed) + 1) % speeds.length];
    await _player.setSpeed(next);
    state = state.copyWith(speed: next);
  }

  Future<void> collapse() async {
    await _player.pause();
    state = state.copyWith(expanded: false);
  }
}
