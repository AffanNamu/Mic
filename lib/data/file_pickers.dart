import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../domain/failures.dart';
import '../domain/services.dart';

/// Limits applied before a picked file is accepted.
abstract final class FileLimits {
  static const lyricsTextBytes = 256 * 1024;
  static const voiceAudioBytes = 25 * 1024 * 1024;
  static const textExtensions = ['txt'];
  static const audioExtensions = [
    'wav',
    'mp3',
    'm4a',
    'aac',
    'ogg',
    'flac',
    'webm',
  ];
}

/// Rejects a lyrics file that is too large to be song lyrics.
void checkLyricsFileSize(int? size) {
  if (size != null && size > FileLimits.lyricsTextBytes) {
    throw const ServiceFailure('That file is too large to be song lyrics.');
  }
}

/// Rejects a voice recording over the upload limit.
void checkVoiceAudioSize(int? size) {
  if (size != null && size > FileLimits.voiceAudioBytes) {
    throw const ServiceFailure(
      'That recording is larger than 25 MB. Choose a shorter one.',
    );
  }
}

/// Decodes a lyrics file as UTF-8, dropping a leading byte-order mark (which
/// Windows editors add to Arabic text files and which would otherwise appear
/// as an invisible character at the start of the lyrics).
PickedText decodeLyricsFile(String fileName, Uint8List bytes) {
  checkLyricsFileSize(bytes.length);
  try {
    final text = utf8.decode(bytes);
    return PickedText(
      fileName: fileName,
      text: text.startsWith('\uFEFF') ? text.substring(1) : text,
    );
  } on FormatException {
    throw const ServiceFailure(
      'That file isn’t UTF-8 text. Save it as UTF-8 and try again.',
    );
  }
}

class PlatformTextFilePicker implements TextFilePicker {
  const PlatformTextFilePicker();

  @override
  Future<PickedText?> pickText() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Import lyrics',
      type: FileType.custom,
      allowedExtensions: FileLimits.textExtensions,
    );
    if (file == null) return null;

    checkLyricsFileSize(await file.length());
    return decodeLyricsFile(file.name, await file.readAsBytes());
  }
}

class PlatformAudioFilePicker implements AudioFilePicker {
  const PlatformAudioFilePicker();

  @override
  Future<PickedAudio?> pickAudio() async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Choose a voice recording',
      type: FileType.custom,
      allowedExtensions: FileLimits.audioExtensions,
    );
    if (file == null) return null;

    checkVoiceAudioSize(await file.length());
    return PickedAudio(fileName: file.name, bytes: await file.readAsBytes());
  }
}
