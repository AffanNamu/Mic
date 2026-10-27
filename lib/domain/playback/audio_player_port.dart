import 'package:flutter/foundation.dart';

/// What the player is doing right now.
@immutable
class PlaybackState {
  const PlaybackState({
    this.loaded = false,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration,
    this.error,
  });

  final bool loaded;
  final bool playing;
  final bool buffering;
  final bool completed;
  final Duration position;

  /// Null until the player has read it from the audio itself.
  final Duration? duration;

  /// A user-safe description of a playback failure.
  final String? error;

  PlaybackState copyWith({
    bool? loaded,
    bool? playing,
    bool? buffering,
    bool? completed,
    Duration? position,
    Duration? duration,
    String? error,
    bool clearError = false,
  }) => PlaybackState(
    loaded: loaded ?? this.loaded,
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    completed: completed ?? this.completed,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  bool operator ==(Object other) =>
      other is PlaybackState &&
      other.loaded == loaded &&
      other.playing == playing &&
      other.buffering == buffering &&
      other.completed == completed &&
      other.position == position &&
      other.duration == duration &&
      other.error == error;

  @override
  int get hashCode => Object.hash(
    loaded,
    playing,
    buffering,
    completed,
    position,
    duration,
    error,
  );
}

/// Audio playback behind a port so screens can be tested without a device.
abstract interface class AudioPlayerPort {
  Stream<PlaybackState> get states;

  /// Opens [url]. Completes when the audio is ready to play or throws if it
  /// cannot be opened.
  Future<void> load(Uri url);

  /// Opens audio held in memory (for example a fresh recording to review).
  Future<void> loadBytes(Uint8List bytes, {required String mimeType});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  Future<void> dispose();
}
