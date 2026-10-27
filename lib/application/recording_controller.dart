import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/recording/record_package_recorder.dart';
import '../domain/failures.dart';
import '../domain/recording/voice_recorder.dart';
import 'providers.dart';

/// Creates the recorder for one recording session. Overridden in tests.
final voiceRecorderFactoryProvider = Provider<VoiceRecorder Function()>(
  (ref) => RecordPackageVoiceRecorder.new,
);

/// What is wrong with a finished recording, if anything.
enum RecordingProblem { tooShort, silent }

sealed class RecordingState {
  const RecordingState();
}

final class RecordingIdle extends RecordingState {
  const RecordingIdle();
}

/// Waiting for the microphone permission / device.
final class RecordingStarting extends RecordingState {
  const RecordingStarting();
}

final class RecordingInProgress extends RecordingState {
  const RecordingInProgress({
    required this.elapsed,
    required this.level,
    required this.limits,
  });

  final Duration elapsed;
  final double level;
  final RecordingLimits limits;
}

final class RecordingReview extends RecordingState {
  const RecordingReview({
    required this.voice,
    required this.limits,
    this.problem,
  });

  final RecordedVoice voice;
  final RecordingLimits limits;

  /// When set the recording should not be used; the user records again.
  final RecordingProblem? problem;
}

final class RecordingError extends RecordingState {
  const RecordingError(this.message);

  final String message;
}

final recordingControllerProvider =
    NotifierProvider.autoDispose<RecordingController, RecordingState>(
      RecordingController.new,
    );

/// Drives one voice recording: permission → capture (stopping by itself at the
/// engine's maximum length) → review. A recording that is too short or silent
/// is flagged and cannot be used, because enrolling a voice can cost money and
/// a bad sample wastes it.
class RecordingController extends Notifier<RecordingState> {
  VoiceRecorder? _recorder;
  StreamSubscription<RecorderProgress>? _progress;
  RecordingLimits _limits = RecordingLimits.fallback;

  @override
  RecordingState build() {
    ref.onDispose(() {
      unawaited(_progress?.cancel());
      final recorder = _recorder;
      if (recorder != null) unawaited(recorder.dispose());
    });
    return const RecordingIdle();
  }

  Future<void> start() async {
    if (state is RecordingStarting || state is RecordingInProgress) return;
    state = const RecordingStarting();

    final capabilities = ref.read(capabilitiesProvider).value;
    _limits = RecordingLimits.fromSeconds(capabilities?.voiceSampleSeconds);

    final recorder = _recorder ??= ref.read(voiceRecorderFactoryProvider)();
    try {
      final stream = await recorder.start();
      state = RecordingInProgress(
        elapsed: Duration.zero,
        level: 0,
        limits: _limits,
      );
      _progress = stream.listen(
        _onProgress,
        onError: (Object e) {
          state = RecordingError(
            e is AppFailure ? e.message : const RecordingFailed().message,
          );
        },
      );
    } on AppFailure catch (e) {
      state = RecordingError(e.message);
    } catch (_) {
      state = RecordingError(const RecordingFailed().message);
    }
  }

  void _onProgress(RecorderProgress p) {
    if (state is! RecordingInProgress) return;
    state = RecordingInProgress(
      elapsed: p.elapsed,
      level: p.level,
      limits: _limits,
    );
    if (p.elapsed >= _limits.max) unawaited(stop());
  }

  Future<void> stop() async {
    if (state is! RecordingInProgress) return;
    final recorder = _recorder;
    if (recorder == null) return;
    // Cancelling removes the listener at once; there is nothing to wait for.
    unawaited(_progress?.cancel());
    _progress = null;
    try {
      final voice = await recorder.stop();
      state = RecordingReview(
        voice: voice,
        limits: _limits,
        problem: voice.duration < _limits.min
            ? RecordingProblem.tooShort
            : (voice.isSilent ? RecordingProblem.silent : null),
      );
    } on AppFailure catch (e) {
      state = RecordingError(e.message);
    } catch (_) {
      state = RecordingError(const RecordingFailed().message);
    }
  }

  /// Stops listening and drops the capture without changing what the screen
  /// shows. For when the screen is already on its way out.
  Future<void> release() async {
    unawaited(_progress?.cancel());
    _progress = null;
    try {
      await _recorder?.cancel();
    } catch (_) {}
  }

  /// Throws the current recording (or capture) away and returns to the start.
  Future<void> discard() async {
    // Cancelling removes the listener at once; there is nothing to wait for.
    unawaited(_progress?.cancel());
    _progress = null;
    try {
      await _recorder?.cancel();
    } catch (_) {}
    state = const RecordingIdle();
  }
}
