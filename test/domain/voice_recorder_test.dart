import 'dart:math' as math;
import 'dart:typed_data';

import 'package:deenvoice/domain/recording/voice_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pcm(List<int> samples) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  return data.buffer.asUint8List();
}

void main() {
  group('wavFromPcm16', () {
    test('writes a valid 44-byte PCM header around the samples', () {
      final samples = pcm([0, 1000, -1000, 32767]);
      final wav = wavFromPcm16(samples, sampleRate: 44100);
      final h = ByteData.sublistView(wav);
      String tag(int o) => String.fromCharCodes(wav.sublist(o, o + 4));

      expect(wav.length, 44 + samples.length);
      expect(tag(0), 'RIFF');
      expect(tag(8), 'WAVE');
      expect(tag(12), 'fmt ');
      expect(tag(36), 'data');
      expect(h.getUint32(4, Endian.little), 36 + samples.length);
      expect(h.getUint16(20, Endian.little), 1, reason: 'PCM');
      expect(h.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(h.getUint32(24, Endian.little), 44100);
      expect(h.getUint32(28, Endian.little), 44100 * 2, reason: 'byte rate');
      expect(h.getUint16(34, Endian.little), 16);
      expect(h.getUint32(40, Endian.little), samples.length);
      expect(wav.sublist(44), samples);
    });

    test('an empty recording is a valid empty WAV', () {
      final wav = wavFromPcm16(Uint8List(0), sampleRate: 16000);
      expect(wav.length, 44);
      expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 0);
    });
  });

  group('pcm16Level', () {
    test('silence is 0 and an empty chunk is 0', () {
      expect(pcm16Level(pcm(List.filled(100, 0))), 0);
      expect(pcm16Level(Uint8List(0)), 0);
    });

    test('full-scale audio is close to 1', () {
      final loud = pcm([
        for (var i = 0; i < 200; i++) i.isEven ? 32767 : -32768,
      ]);
      expect(pcm16Level(loud), closeTo(1, 0.01));
    });

    test('is louder for louder audio and follows dBFS (-30 dB ≈ 0.5)', () {
      final amp = (32768 * math.pow(10, -30 / 20)).round();
      final mid = pcm([for (var i = 0; i < 200; i++) i.isEven ? amp : -amp]);
      final quiet = pcm([for (var i = 0; i < 200; i++) i.isEven ? 20 : -20]);
      expect(pcm16Level(mid), closeTo(0.5, 0.02));
      expect(pcm16Level(quiet), lessThan(pcm16Level(mid)));
    });
  });

  group('RecordingLimits', () {
    test('use the engine\'s stated range, or a conservative fallback', () {
      final stated = RecordingLimits.fromSeconds((min: 5, max: 15));
      expect(stated.min, const Duration(seconds: 5));
      expect(stated.max, const Duration(seconds: 15));
      expect(RecordingLimits.fromSeconds(null), RecordingLimits.fallback);
    });
  });

  group('RecordedVoice', () {
    test('a recording with almost no signal is silent', () {
      final quiet = RecordedVoice(
        wav: Uint8List(44),
        duration: const Duration(seconds: 9),
        peakLevel: 0.02,
        averageLevel: 0.01,
      );
      final ok = RecordedVoice(
        wav: Uint8List(44),
        duration: const Duration(seconds: 9),
        peakLevel: 0.5,
        averageLevel: 0.3,
      );
      expect(quiet.isSilent, isTrue);
      expect(ok.isSilent, isFalse);
    });
  });
}
