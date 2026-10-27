// Test doubles. These exist only under test/ and must never be mistaken for
// evidence that real generation, voice enrollment or billing works.
import 'dart:async';

import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/generation/generation_request.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';

class FakeVoiceRepository implements VoiceRepository {
  FakeVoiceRepository(List<VoiceProfile> voices) : voices = [...voices];

  final List<VoiceProfile> voices;
  final enrollments = <VoiceEnrollment>[];

  @override
  Future<List<VoiceProfile>> listVoices() async => [...voices];

  @override
  Future<VoiceProfile> enrollVoice(VoiceEnrollment enrollment) async {
    enrollments.add(enrollment);
    final profile = VoiceProfile(
      id: 'enrolled-${enrollments.length}',
      displayName: enrollment.displayName,
      kind: VoiceKind.own,
      status: VoiceStatus.enrolling,
      supportsSinging: true,
    );
    voices.add(profile);
    return profile;
  }

  @override
  Future<String?> deleteVoice(String voiceId) async {
    voices.removeWhere((v) => v.id == voiceId);
    return deleteDisclosure;
  }

  /// What the (fake) service says it could not remove.
  String? deleteDisclosure;
}

class FakeCreditsRepository implements CreditsRepository {
  FakeCreditsRepository(this.credits);

  int credits;

  @override
  Future<int> balance() async => credits;
}

class FakeLyricsAssistant implements LyricsAssistant {
  FakeLyricsAssistant({this.writeResult, this.improveResult, this.failure});

  final LyricsSuggestion? writeResult;
  final LyricsSuggestion? improveResult;
  final AppFailure? failure;

  @override
  Future<LyricsSuggestion> write(LyricsRequest request) async {
    if (failure != null) throw failure!;
    return writeResult ?? const LyricsSuggestion('Test lyrics');
  }

  @override
  Future<LyricsSuggestion> improve({
    required String lyrics,
    required SongLanguage language,
  }) async {
    if (failure != null) throw failure!;
    return improveResult ?? LyricsSuggestion('$lyrics (improved)');
  }
}

class FakeGenerationService implements SongGenerationService {
  FakeGenerationService({GenerationCapabilities? capabilities, this.failure})
    : _capabilities = capabilities ?? fullCapabilities;

  static const fullCapabilities = GenerationCapabilities(
    engineName: 'Test Engine',
    songTypes: {...SongType.values},
    languages: {...SongLanguage.values},
    voiceConditioning: true,
    advancedOptionIds: {'pitch_range', 'vocal_style'},
  );

  final GenerationCapabilities _capabilities;
  AppFailure? failure;

  /// If set, thrown from [submit] (simulates a non-AppFailure transport error).
  Object? unexpectedError;
  final submitted = <GenerationRequest>[];

  /// Completes submissions manually when set, to test in-flight behaviour.
  Completer<GenerationReceipt>? gate;

  @override
  Future<GenerationCapabilities> capabilities() async => _capabilities;

  @override
  Future<GenerationReceipt> submit(GenerationRequest request) async {
    submitted.add(request);
    if (gate != null) return gate!.future;
    if (unexpectedError != null) throw unexpectedError!;
    if (failure != null) throw failure!;
    return GenerationReceipt(
      jobId: 'job-${submitted.length}',
      status: GenerationStatus.queued,
      creditsReserved: request.estimatedCredits,
    );
  }
}

class FakeTextFilePicker implements TextFilePicker {
  FakeTextFilePicker(this.result, {this.error});

  final PickedText? result;
  final AppFailure? error;

  @override
  Future<PickedText?> pickText() async {
    if (error != null) throw error!;
    return result;
  }
}

class FakeAudioFilePicker implements AudioFilePicker {
  FakeAudioFilePicker(this.result, {this.error});

  final PickedAudio? result;
  final AppFailure? error;

  @override
  Future<PickedAudio?> pickAudio() async {
    if (error != null) throw error!;
    return result;
  }
}

const readyOwnVoice = VoiceProfile(
  id: 'voice-own',
  displayName: 'My Voice',
  kind: VoiceKind.own,
  status: VoiceStatus.ready,
  supportsSinging: true,
  avatarUrl: 'avatar-a',
);

const readyAuthorizedVoice = VoiceProfile(
  id: 'voice-aisha',
  displayName: 'Sister Aisha',
  kind: VoiceKind.authorized,
  status: VoiceStatus.ready,
  supportsSinging: true,
  presentation: VoicePresentation.female,
  avatarUrl: 'avatar-b',
);

const readySystemVoice = VoiceProfile(
  id: 'voice-studio',
  displayName: 'Studio Voice',
  kind: VoiceKind.system,
  status: VoiceStatus.ready,
  supportsSinging: true,
);
