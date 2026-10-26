import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/file_pickers.dart';
import '../data/unconfigured_services.dart';
import '../domain/credits/pricing.dart';
import '../domain/generation/generation_capabilities.dart';
import '../domain/services.dart';
import '../domain/song/song_validation.dart';
import '../domain/voice/voice_profile.dart';
import 'song_draft_notifier.dart';

// --- Integration boundaries -------------------------------------------------
// Override these in `ProviderScope` once real backend clients exist.

final voiceRepositoryProvider = Provider<VoiceRepository>(
  (ref) => const UnconfiguredVoiceRepository(),
);

final creditsRepositoryProvider = Provider<CreditsRepository>(
  (ref) => const UnconfiguredCreditsRepository(),
);

final lyricsAssistantProvider = Provider<LyricsAssistant>(
  (ref) => const UnconfiguredLyricsAssistant(),
);

final songGenerationServiceProvider = Provider<SongGenerationService>(
  (ref) => const UnconfiguredSongGenerationService(),
);

final textFilePickerProvider = Provider<TextFilePicker>(
  (ref) => const PlatformTextFilePicker(),
);

final audioFilePickerProvider = Provider<AudioFilePicker>(
  (ref) => const PlatformAudioFilePicker(),
);

// --- Remote state -----------------------------------------------------------

final voicesProvider = FutureProvider<List<VoiceProfile>>(
  (ref) => ref.watch(voiceRepositoryProvider).listVoices(),
);

final creditBalanceProvider = FutureProvider<int>(
  (ref) => ref.watch(creditsRepositoryProvider).balance(),
);

final capabilitiesProvider = FutureProvider<GenerationCapabilities>(
  (ref) => ref.watch(songGenerationServiceProvider).capabilities(),
);

// --- Draft ------------------------------------------------------------------

final songDraftProvider = NotifierProvider<SongDraftNotifier, SongDraftState>(
  SongDraftNotifier.new,
);

/// The voice that will be used: the user's explicit pick if it still exists,
/// otherwise their first ready personal voice. Never a made-up default.
final selectedVoiceIdProvider = Provider<String?>((ref) {
  final voices = ref.watch(voicesProvider).value ?? const <VoiceProfile>[];
  final explicit = ref.watch(songDraftProvider.select((s) => s.draft.voiceId));
  if (explicit != null && voices.any((v) => v.id == explicit)) return explicit;
  return voices
      .where((v) => v.isSelectable && v.kind == VoiceKind.own)
      .firstOrNull
      ?.id;
});

final draftIssuesProvider = Provider<List<DraftIssue>>((ref) {
  return validateDraft(
    ref.watch(songDraftProvider).draft,
    voices: ref.watch(voicesProvider).value ?? const [],
    effectiveVoiceId: ref.watch(selectedVoiceIdProvider),
    capabilities:
        ref.watch(capabilitiesProvider).value ?? GenerationCapabilities.none,
  );
});

/// Progress through the four steps, derived from the real draft.
final stepProgressProvider =
    Provider<({Set<SongStep> completed, SongStep active})>((ref) {
      final draft = ref.watch(songDraftProvider).draft;
      final voices = ref.watch(voicesProvider).value ?? const <VoiceProfile>[];
      final voiceId = ref.watch(selectedVoiceIdProvider);
      final voiceReady = voices.any((v) => v.id == voiceId && v.isSelectable);
      final completed = completedSteps(draft, voiceReady: voiceReady);
      return (completed: completed, active: activeStep(completed));
    });

final estimatedCreditsProvider = Provider<int>(
  (ref) => estimateCredits(ref.watch(songDraftProvider).draft),
);
