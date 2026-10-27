import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/api/api_client.dart';
import '../data/api/http_services.dart';
import '../data/api/session_store.dart';
import '../data/audio/just_audio_player.dart';
import '../data/file_pickers.dart';
import '../data/unconfigured_services.dart';
import '../domain/auth/auth.dart';
import '../domain/credits/pricing.dart';
import '../domain/failures.dart';
import '../domain/generation/generation_capabilities.dart';
import '../domain/library/library.dart';
import '../domain/playback/audio_player_port.dart';
import '../domain/services.dart';
import '../domain/song/song_validation.dart';
import '../domain/voice/consent.dart';
import '../domain/voice/voice_profile.dart';
import 'session_controller.dart';
import 'song_draft_notifier.dart';

// --- Backend connection -----------------------------------------------------
// With no API_BASE_URL the app runs exactly as an unconnected build: every
// service below is its honest `Unconfigured*` stand-in.

/// Base URL of the DeenVoice backend, set at build time:
/// `--dart-define=API_BASE_URL=https://api.example.com`. Provider credentials
/// are never part of the app; the backend holds them.
final apiBaseUrlProvider = Provider<String>(
  (ref) => const String.fromEnvironment('API_BASE_URL'),
);

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => const PreferencesSessionStore(),
);

/// Injectable clock (tests).
final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

/// Null when no backend is configured.
final apiClientProvider = Provider<ApiClient?>((ref) {
  final base = ref.watch(apiBaseUrlProvider);
  if (base.isEmpty) return null;
  final session = ref.watch(sessionProvider).value;
  return ApiClient(
    baseUrl: Uri.parse(base),
    client: ref.watch(httpClientProvider),
    token: session?.token,
    onUnauthorized: () =>
        unawaited(ref.read(sessionProvider.notifier).expire()),
  );
});

final authServiceProvider = Provider<AuthService?>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? null : HttpAuthService(api);
});

final consentSourceProvider = Provider<ConsentSource?>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? null : HttpConsentSource(api);
});

/// The server-owned consent wording, or null when no backend is connected
/// (the sheet then falls back to its own local wording and no version).
final consentStatementsProvider = FutureProvider<ConsentStatements?>((ref) {
  return ref.watch(consentSourceProvider)?.statements();
});

/// How often to re-check voices that are still enrolling. Null (the default)
/// disables polling; the app enables it when a backend is connected.
final voicePollIntervalProvider = Provider<Duration?>((ref) => null);

final jobPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 3),
);

final generationJobsProvider = Provider<GenerationJobs?>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? null : HttpGenerationJobs(api);
});

final songLibraryProvider = Provider<SongLibrary?>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null ? null : HttpSongLibrary(api);
});

final audioPlayerFactoryProvider = Provider<AudioPlayerPort Function()>(
  (ref) => JustAudioPlayer.new,
);

// --- Integration boundaries -------------------------------------------------
// Tests override these directly with fakes.

final voiceRepositoryProvider = Provider<VoiceRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null
      ? const UnconfiguredVoiceRepository()
      : HttpVoiceRepository(api);
});

final creditsRepositoryProvider = Provider<CreditsRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null
      ? const UnconfiguredCreditsRepository()
      : HttpCreditsRepository(api);
});

final lyricsAssistantProvider = Provider<LyricsAssistant>(
  (ref) => const UnconfiguredLyricsAssistant(),
);

final songGenerationServiceProvider = Provider<SongGenerationService>((ref) {
  final api = ref.watch(apiClientProvider);
  return api == null
      ? const UnconfiguredSongGenerationService()
      : HttpSongGenerationService(api);
});

final textFilePickerProvider = Provider<TextFilePicker>(
  (ref) => const PlatformTextFilePicker(),
);

final audioFilePickerProvider = Provider<AudioFilePicker>(
  (ref) => const PlatformAudioFilePicker(),
);

// --- Remote state -----------------------------------------------------------

final voicesProvider = FutureProvider<List<VoiceProfile>>((ref) async {
  final voices = await ref.watch(voiceRepositoryProvider).listVoices();
  // A voice that is still being enrolled becomes ready (or failed) on the
  // server without the app being told, so ask again until none is pending.
  final interval = ref.watch(voicePollIntervalProvider);
  if (interval != null &&
      voices.any((v) => v.status == VoiceStatus.enrolling)) {
    final timer = Timer(interval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return voices;
});

/// The user's saved songs. Empty when no library is connected.
final songsProvider = FutureProvider.autoDispose<List<SongRecord>>((ref) async {
  final library = ref.watch(songLibraryProvider);
  return library == null ? const [] : library.list();
});

/// Recent generation jobs, newest first.
final recentJobsProvider = FutureProvider.autoDispose<List<GenerationJob>>((
  ref,
) async {
  final jobs = ref.watch(generationJobsProvider);
  return jobs == null ? const [] : jobs.recent();
});

/// Follows one job until it finishes, using only what the server reports.
/// Transient network errors are retried; a rejected session or repeated
/// failures end the stream with an error rather than inventing progress.
final jobWatchProvider = StreamProvider.autoDispose
    .family<GenerationJob, String>((ref, jobId) async* {
      final jobs = ref.watch(generationJobsProvider);
      if (jobs == null) throw const ServiceNotConfigured('Progress tracking');
      var failures = 0;
      while (true) {
        try {
          final job = await jobs.job(jobId);
          failures = 0;
          yield job;
          if (job.status.isFinished) return;
        } on SessionExpired {
          rethrow;
        } on AppFailure {
          if (++failures >= 5) rethrow;
        }
        await Future<void>.delayed(ref.read(jobPollIntervalProvider));
      }
    });

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
