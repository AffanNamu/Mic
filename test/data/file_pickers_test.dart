import 'dart:convert';
import 'dart:typed_data';

import 'package:deenvoice/data/file_pickers.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeLyricsFile', () {
    test('decodes Hausa, Arabic and English text', () {
      const text = 'Ya Allah, ka ji mu\nيا رب ارحمنا\nPraise be';
      final picked = decodeLyricsFile('nasheed.txt', utf8.encode(text));
      expect(picked.fileName, 'nasheed.txt');
      expect(picked.text, text);
    });

    test('drops a leading UTF-8 byte-order mark', () {
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('يا رب'),
      ]);
      expect(decodeLyricsFile('a.txt', bytes).text, 'يا رب');
    });

    test('rejects bytes that are not UTF-8 with a clear message', () {
      expect(
        () => decodeLyricsFile(
          'bad.txt',
          Uint8List.fromList([0xFF, 0xFE, 0x41, 0x80]),
        ),
        throwsA(
          isA<ServiceFailure>().having(
            (e) => e.message,
            'message',
            contains('isn’t UTF-8'),
          ),
        ),
      );
    });

    test('rejects files over the lyrics size limit', () {
      final big = Uint8List(FileLimits.lyricsTextBytes + 1);
      expect(
        () => decodeLyricsFile('big.txt', big),
        throwsA(isA<ServiceFailure>()),
      );
    });

    test('accepts a file exactly at the limit', () {
      final edge = Uint8List.fromList(
        List.filled(FileLimits.lyricsTextBytes, 0x61),
      );
      expect(
        decodeLyricsFile('edge.txt', edge).text.length,
        FileLimits.lyricsTextBytes,
      );
    });
  });

  group('size checks', () {
    test('unknown sizes are allowed through (checked again on read)', () {
      expect(() => checkLyricsFileSize(null), returnsNormally);
      expect(() => checkVoiceAudioSize(null), returnsNormally);
    });

    test('voice audio over 25 MB is rejected', () {
      expect(
        () => checkVoiceAudioSize(FileLimits.voiceAudioBytes),
        returnsNormally,
      );
      expect(
        () => checkVoiceAudioSize(FileLimits.voiceAudioBytes + 1),
        throwsA(
          isA<ServiceFailure>().having(
            (e) => e.message,
            'message',
            contains('25 MB'),
          ),
        ),
      );
    });
  });

  test('accepted audio formats cover common recorder outputs', () {
    expect(
      FileLimits.audioExtensions,
      containsAll(['wav', 'mp3', 'm4a', 'aac', 'ogg', 'flac', 'webm']),
    );
  });

  group('VoiceProfile value semantics', () {
    VoiceProfile make({String name = 'V', bool sings = true}) => VoiceProfile(
      id: 'v',
      displayName: name,
      kind: VoiceKind.own,
      status: VoiceStatus.ready,
      supportsSinging: sings,
    );

    test('equal when all fields match, and hash agrees', () {
      expect(make(), make());
      expect(make().hashCode, make().hashCode);
    });

    test('differs when any field differs', () {
      expect(make(), isNot(make(name: 'W')));
      expect(make(), isNot(make(sings: false)));
    });
  });
}
