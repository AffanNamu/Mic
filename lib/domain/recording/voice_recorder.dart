import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// One reading from the microphone while recording.
@immutable
class RecorderProgress {
  const RecorderProgress({required this.elapsed, required this.level});

  /// Audio captured so far, measured from the samples themselves (not a timer).
  final Duration elapsed;

  /// Loudness of the latest audio, 0 (silence) to 1 (very loud).
  final double level;
}

/// A finished recording: 16-bit mono PCM in a WAV container, so its length is
/// exact and every platform produces the same format.
@immutable
class RecordedVoice {
  const RecordedVoice({
    required this.wav,
    required this.duration,
    required this.peakLevel,
    required this.averageLevel,
  });

  final Uint8List wav;
  final Duration duration;

  /// Loudest and average loudness (0–1) over the whole recording; used to
  /// catch a muted or disconnected microphone before the recording is used.
  final double peakLevel;
  final double averageLevel;

  String get fileName => 'recording.wav';

  /// True when almost nothing was captured.
  bool get isSilent => peakLevel < silentPeakThreshold;

  static const silentPeakThreshold = 0.08;
}

/// Microphone capture behind a port, so screens are tested without hardware.
abstract interface class VoiceRecorder {
  /// Asks for permission if needed and starts capturing. Throws
  /// `MicrophoneUnavailable` if access is refused. The stream ends when
  /// [stop] or [cancel] is called.
  Future<Stream<RecorderProgress>> start();

  /// Ends the capture and returns what was recorded.
  Future<RecordedVoice> stop();

  /// Ends the capture and throws the audio away.
  Future<void> cancel();

  Future<void> dispose();
}

/// How long a voice recording should be.
@immutable
class RecordingLimits {
  const RecordingLimits({required this.min, required this.max});

  /// Used when the engine does not state a length: a conservative window that
  /// is long enough to carry a voice and short enough to review.
  static const fallback = RecordingLimits(
    min: Duration(seconds: 5),
    max: Duration(seconds: 30),
  );

  final Duration min;
  final Duration max;

  factory RecordingLimits.fromSeconds(({int min, int max})? seconds) =>
      seconds == null
      ? fallback
      : RecordingLimits(
          min: Duration(seconds: seconds.min),
          max: Duration(seconds: seconds.max),
        );

  @override
  bool operator ==(Object other) =>
      other is RecordingLimits && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// Wraps raw little-endian 16-bit PCM in a 44-byte WAV header.
Uint8List wavFromPcm16(
  Uint8List pcm, {
  required int sampleRate,
  int channels = 1,
}) {
  final out = ByteData(44 + pcm.length);
  void ascii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  out.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little); // PCM
  out.setUint16(22, channels, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * channels * 2, Endian.little);
  out.setUint16(32, channels * 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  out.setUint32(40, pcm.length, Endian.little);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(44, 44 + pcm.length, pcm);
  return bytes;
}

/// Loudness of a chunk of 16-bit PCM on a 0–1 scale (RMS in dBFS, with
/// −60 dB as silence and 0 dB as full scale).
double pcm16Level(Uint8List pcm) {
  final samples = pcm.length ~/ 2;
  if (samples == 0) return 0;
  final view = ByteData.sublistView(pcm);
  var sumSquares = 0.0;
  for (var i = 0; i < samples; i++) {
    final s = view.getInt16(i * 2, Endian.little) / 32768.0;
    sumSquares += s * s;
  }
  final rms = math.sqrt(sumSquares / samples);
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 60) / 60).clamp(0.0, 1.0);
}
