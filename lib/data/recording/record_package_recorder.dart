import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../../domain/failures.dart';
import '../../domain/recording/voice_recorder.dart';

/// Captures the microphone with the `record` package as a PCM stream and wraps
/// it in a WAV. Streaming PCM is supported on every platform (including web),
/// which keeps the output identical everywhere and lets the loudness and
/// elapsed time come from the samples themselves.
class RecordPackageVoiceRecorder implements VoiceRecorder {
  RecordPackageVoiceRecorder({AudioRecorder? recorder, this.sampleRate = 44100})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final int sampleRate;

  final _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  StreamController<RecorderProgress>? _progress;
  var _peak = 0.0;
  var _levelSum = 0.0;
  var _chunks = 0;

  Duration get _elapsed =>
      Duration(microseconds: _pcm.length * 1000000 ~/ (sampleRate * 2));

  @override
  Future<Stream<RecorderProgress>> start() async {
    final bool allowed;
    try {
      allowed = await _recorder.hasPermission();
    } catch (_) {
      throw const MicrophoneUnavailable();
    }
    if (!allowed) throw const MicrophoneUnavailable();

    _pcm.clear();
    _peak = 0;
    _levelSum = 0;
    _chunks = 0;
    final progress = StreamController<RecorderProgress>();
    _progress = progress;

    final Stream<Uint8List> audio;
    try {
      audio = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );
    } catch (_) {
      await progress.close();
      throw const MicrophoneUnavailable(
        'No microphone could be started. Check that one is connected and '
        'not in use by another app.',
      );
    }

    _subscription = audio.listen(
      (chunk) {
        _pcm.add(chunk);
        final level = pcm16Level(chunk);
        if (level > _peak) _peak = level;
        _levelSum += level;
        _chunks++;
        if (!progress.isClosed) {
          progress.add(RecorderProgress(elapsed: _elapsed, level: level));
        }
      },
      onError: (Object _) {
        if (!progress.isClosed) progress.addError(const RecordingFailed());
      },
    );
    return progress.stream;
  }

  @override
  Future<RecordedVoice> stop() async {
    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    await _progress?.close();
    _progress = null;

    if (_pcm.length == 0) throw const RecordingFailed('Nothing was recorded.');
    final pcm = _pcm.takeBytes();
    return RecordedVoice(
      wav: wavFromPcm16(pcm, sampleRate: sampleRate),
      duration: Duration(
        microseconds: pcm.length * 1000000 ~/ (sampleRate * 2),
      ),
      peakLevel: _peak,
      averageLevel: _chunks == 0 ? 0 : _levelSum / _chunks,
    );
  }

  @override
  Future<void> cancel() async {
    try {
      await _recorder.cancel();
    } catch (_) {}
    await _subscription?.cancel();
    _subscription = null;
    await _progress?.close();
    _progress = null;
    _pcm.clear();
  }

  @override
  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
