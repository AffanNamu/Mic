import '../domain/failures.dart';
import '../domain/generation/generation_capabilities.dart';
import '../domain/generation/generation_request.dart';
import '../domain/services.dart';
import '../domain/song/song_options.dart';
import '../domain/voice/voice_profile.dart';

/// Stand-ins used until the DeenVoice backend is connected.
///
/// They never invent data: lists are empty, capabilities are `none`, and every
/// operation that needs a real service throws [ServiceNotConfigured] so the UI
/// can say exactly what is missing.

class UnconfiguredVoiceRepository implements VoiceRepository {
  const UnconfiguredVoiceRepository();

  @override
  Future<List<VoiceProfile>> listVoices() async => const [];

  @override
  Future<VoiceProfile> enrollVoice(VoiceEnrollment enrollment) =>
      Future.error(const ServiceNotConfigured('Voice enrollment'));

  @override
  Future<void> deleteVoice(String voiceId) =>
      Future.error(const ServiceNotConfigured('Voice management'));
}

class UnconfiguredCreditsRepository implements CreditsRepository {
  const UnconfiguredCreditsRepository();

  @override
  Future<int> balance() =>
      Future.error(const ServiceNotConfigured('Your credit balance'));
}

class UnconfiguredLyricsAssistant implements LyricsAssistant {
  const UnconfiguredLyricsAssistant();

  @override
  Future<LyricsSuggestion> write(LyricsRequest request) =>
      Future.error(const ServiceNotConfigured('The lyrics assistant'));

  @override
  Future<LyricsSuggestion> improve({
    required String lyrics,
    required SongLanguage language,
  }) => Future.error(const ServiceNotConfigured('The lyrics assistant'));
}

class UnconfiguredSongGenerationService implements SongGenerationService {
  const UnconfiguredSongGenerationService();

  @override
  Future<GenerationCapabilities> capabilities() async =>
      GenerationCapabilities.none;

  @override
  Future<GenerationReceipt> submit(GenerationRequest request) =>
      Future.error(const ServiceNotConfigured('Song generation'));
}
