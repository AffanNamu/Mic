import 'dart:async';

import 'package:just_audio/just_audio.dart';

import '../../domain/playback/audio_player_port.dart';

/// [AudioPlayerPort] backed by `just_audio` (HTML audio on web, the platform
/// players on mobile).
class JustAudioPlayer implements AudioPlayerPort {
  JustAudioPlayer() {
    _subscriptions.addAll([
      _player.playerStateStream.listen((s) {
        _emit(
          _state.copyWith(
            playing: s.playing,
            buffering:
                s.processingState == ProcessingState.loading ||
                s.processingState == ProcessingState.buffering,
            completed: s.processingState == ProcessingState.completed,
          ),
        );
      }),
      _player.positionStream.listen((p) => _emit(_state.copyWith(position: p))),
      _player.durationStream.listen((d) {
        if (d != null) _emit(_state.copyWith(duration: d));
      }),
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object _) => _emit(
          _state.copyWith(
            playing: false,
            error: 'This song couldn’t be played. Try again.',
          ),
        ),
      ),
    ]);
  }

  final AudioPlayer _player = AudioPlayer();
  final _controller = StreamController<PlaybackState>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  PlaybackState _state = const PlaybackState();

  void _emit(PlaybackState next) {
    if (next == _state) return;
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Stream<PlaybackState> get states => _controller.stream;

  @override
  Future<void> load(Uri url) async {
    _emit(const PlaybackState(buffering: true));
    try {
      final duration = await _player.setUrl(url.toString());
      _emit(
        _state.copyWith(
          loaded: true,
          buffering: false,
          duration: duration,
          clearError: true,
        ),
      );
    } on PlayerException {
      _emit(
        _state.copyWith(
          buffering: false,
          error: 'This song couldn’t be opened.',
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    // just_audio's play() completes when playback ends, so it is not awaited.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _player.dispose();
    await _controller.close();
  }
}
