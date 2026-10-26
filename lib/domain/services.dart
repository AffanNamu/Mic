import 'dart:typed_data';

import 'generation/generation_capabilities.dart';
import 'generation/generation_request.dart';
import 'song/song_options.dart';
import 'voice/voice_profile.dart';

/// Integration boundaries. Production implementations talk to the DeenVoice
/// backend (which holds all provider credentials); this build only ships
/// `Unconfigured*` implementations in `data/`, which fail honestly.

abstract interface class VoiceRepository {
  Future<List<VoiceProfile>> listVoices();

  /// Starts enrollment of a new voice from authorized audio. Returns the
  /// profile in `enrolling` state.
  Future<VoiceProfile> enrollVoice(VoiceEnrollment enrollment);

  Future<void> deleteVoice(String voiceId);
}

/// Audio plus the consent that makes it usable.
class VoiceEnrollment {
  const VoiceEnrollment({
    required this.displayName,
    required this.fileName,
    required this.audio,
    required this.consent,
  });

  final String displayName;
  final String fileName;
  final Uint8List audio;
  final VoiceConsent consent;
}

enum VoiceOwnership { ownVoice, authorizedByOwner }

class VoiceConsent {
  const VoiceConsent({required this.ownership, required this.acceptedAt});

  final VoiceOwnership ownership;
  final DateTime acceptedAt;
}

abstract interface class CreditsRepository {
  Future<int> balance();
}

class LyricsRequest {
  const LyricsRequest({
    required this.theme,
    required this.language,
    required this.genre,
    required this.mood,
  });

  final String theme;
  final SongLanguage language;
  final SongGenre genre;
  final SongMood mood;
}

class LyricsSuggestion {
  const LyricsSuggestion(this.lyrics, {this.notes = const []});

  final String lyrics;

  /// Caveats for the user to review (uncertain pronunciation, unverified
  /// religious wording, language limits).
  final List<String> notes;
}

abstract interface class LyricsAssistant {
  Future<LyricsSuggestion> write(LyricsRequest request);

  /// Improves flow and singability without silently changing religious text.
  Future<LyricsSuggestion> improve({
    required String lyrics,
    required SongLanguage language,
  });
}

abstract interface class SongGenerationService {
  Future<GenerationCapabilities> capabilities();

  /// Submits a job. Must be idempotent on `request.idempotencyKey`.
  Future<GenerationReceipt> submit(GenerationRequest request);
}

/// Reads a UTF-8 text file chosen by the user.
abstract interface class TextFilePicker {
  /// Returns null if the user cancelled.
  Future<PickedText?> pickText();
}

class PickedText {
  const PickedText({required this.fileName, required this.text});

  final String fileName;
  final String text;
}

/// Reads an audio file chosen by the user (for voice enrollment).
abstract interface class AudioFilePicker {
  /// Returns null if the user cancelled.
  Future<PickedAudio?> pickAudio();
}

class PickedAudio {
  const PickedAudio({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}
