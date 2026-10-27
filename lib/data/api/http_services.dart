import '../../domain/auth/auth.dart';
import '../../domain/failures.dart';
import '../../domain/generation/generation_capabilities.dart';
import '../../domain/generation/generation_request.dart';
import '../../domain/library/library.dart';
import '../../domain/services.dart';
import '../../domain/song/song_options.dart';
import '../../domain/song/song_type.dart';
import '../../domain/voice/consent.dart';
import '../../domain/voice/voice_profile.dart';
import 'api_client.dart';
import 'json.dart';

/// Turns a server error into something safe to show. Server messages are
/// written for users; transport and session failures already are AppFailures.
Future<T> guard<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on ApiException catch (e) {
    throw ServiceFailure(e.message);
  }
}

class HttpAuthService implements AuthService {
  const HttpAuthService(this._api);

  final ApiClient _api;

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
  }) => _open('/v1/auth/register', email, password);

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) => _open('/v1/auth/login', email, password);

  Future<AuthSession> _open(String path, String email, String password) =>
      guard(() async {
        final j = asObject(
          await _api.postPublic(
            path,
            json: {'email': email.trim(), 'password': password},
          ),
        );
        return AuthSession(
          token: str(j, 'token'),
          userId: str(j, 'userId'),
          email: str(j, 'email'),
          expiresAt: time(j, 'expiresAt'),
        );
      });

  @override
  Future<void> signOut() async {
    try {
      await _api.post('/v1/auth/logout');
    } catch (_) {
      // Local sign-out proceeds regardless; the token also expires on its own.
    }
  }
}

class HttpConsentSource implements ConsentSource {
  const HttpConsentSource(this._api);

  final ApiClient _api;

  @override
  Future<ConsentStatements> statements() => guard(() async {
    final j = asObject(await _api.getPublic('/v1/consent-statements'));
    final texts = <VoiceOwnership, String>{};
    for (final item in asList(j['statements'])) {
      final s = asObject(item);
      switch (str(s, 'ownership')) {
        case 'own':
          texts[VoiceOwnership.ownVoice] = str(s, 'text');
        case 'authorized':
          texts[VoiceOwnership.authorizedByOwner] = str(s, 'text');
      }
    }
    return ConsentStatements(version: str(j, 'version'), texts: texts);
  });
}

class HttpVoiceRepository implements VoiceRepository {
  const HttpVoiceRepository(this._api);

  final ApiClient _api;

  @override
  Future<List<VoiceProfile>> listVoices() => guard(() async {
    final j = asObject(await _api.get('/v1/voices'));
    return [for (final v in asList(j['voices'])) _profile(asObject(v))];
  });

  @override
  Future<VoiceProfile> enrollVoice(VoiceEnrollment enrollment) => guard(
    () async {
      final version = enrollment.consent.statementVersion;
      if (version == null) {
        // Without the server's own wording nothing can be recorded as agreed.
        throw const ServiceFailure(
          'The consent statement could not be loaded, so this voice can’t be '
          'added yet. Reload and try again.',
        );
      }
      final created = asObject(
        await _api.post(
          '/v1/voices',
          json: {
            'displayName': enrollment.displayName,
            'ownership': enrollment.consent.ownership == VoiceOwnership.ownVoice
                ? 'own'
                : 'authorized',
            'authorizedBy': enrollment.consent.authorizedBy,
            'consent': {'accepted': true, 'version': version},
          },
        ),
      );
      final id = str(asObject(created['voice']), 'id');
      try {
        final uploaded = asObject(
          await _api.putBytes(
            '/v1/voices/$id/audio',
            enrollment.audio,
            contentType: _audioType(enrollment.fileName),
          ),
        );
        return _profile(asObject(uploaded['voice']));
      } catch (_) {
        // Do not leave a consented voice with no recording behind.
        try {
          await _api.delete('/v1/voices/$id');
        } catch (_) {}
        rethrow;
      }
    },
  );

  @override
  Future<String?> deleteVoice(String voiceId) => guard(() async {
    final j = asObject(
      await _api.delete(
        '/v1/voices/${Uri.encodeComponent(voiceId)}',
        query: {'deleteSongs': 'false'},
      ),
    );
    return strOrNull(j, 'disclosure');
  });

  static VoiceProfile _profile(Json v) {
    final status = switch (str(v, 'status')) {
      'ready' => VoiceStatus.ready,
      'revoked' => VoiceStatus.revoked,
      // A voice still waiting for its recording never finished enrolling.
      'failed' || 'awaiting_audio' => VoiceStatus.failed,
      _ => VoiceStatus.enrolling,
    };
    return VoiceProfile(
      id: str(v, 'id'),
      displayName: str(v, 'displayName'),
      kind: str(v, 'ownership') == 'own' ? VoiceKind.own : VoiceKind.authorized,
      status: status,
      supportsSinging: flag(v, 'supportsSinging'),
      detail: status == VoiceStatus.failed
          ? strOrNull(v, 'failureMessage')
          : null,
    );
  }

  static String _audioType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return switch (ext) {
      'wav' => 'audio/wav',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'aac' => 'audio/aac',
      'ogg' => 'audio/ogg',
      'flac' => 'audio/flac',
      'webm' => 'audio/webm',
      _ => 'application/octet-stream',
    };
  }
}

class HttpCreditsRepository implements CreditsRepository {
  const HttpCreditsRepository(this._api);

  final ApiClient _api;

  @override
  Future<int> balance() => guard(() async {
    return integer(asObject(await _api.get('/v1/credits')), 'available');
  });
}

class HttpSongGenerationService implements SongGenerationService {
  const HttpSongGenerationService(this._api);

  final ApiClient _api;

  @override
  Future<GenerationCapabilities> capabilities() => guard(() async {
    final j = asObject(await _api.get('/v1/generation/capabilities'));
    final engine = strOrNull(j, 'engineName');
    if (engine == null) return GenerationCapabilities.none;

    Set<T> pick<T>(String key, Iterable<T> all, String Function(T) id) {
      final wanted = {for (final v in asList(j[key])) v as String};
      // Ids this app version doesn't know are dropped, never guessed at.
      return {
        for (final v in all)
          if (wanted.contains(id(v))) v,
      };
    }

    return GenerationCapabilities(
      engineName: engine,
      songTypes: pick('songTypes', SongType.values, (t) => t.id),
      languages: pick('languages', SongLanguage.values, (l) => l.id),
      voiceConditioning: flag(j, 'voiceConditioning'),
      advancedOptionIds: {
        for (final v in asList(j['advancedOptionIds'])) v as String,
      },
      voiceSampleSeconds: _sampleSeconds(j['voiceSampleSeconds']),
      unavailableReason: flag(j, 'available')
          ? null
          : '$engine is temporarily unavailable. Please try again later.',
    );
  });

  @override
  Future<GenerationReceipt> submit(GenerationRequest request) async {
    final d = request.draft;
    try {
      final j = asObject(
        await _api.post(
          '/v1/generation/jobs',
          json: {
            'idempotencyKey': request.idempotencyKey,
            'title': d.title.trim(),
            'lyrics': d.type.usesLyrics ? d.lyrics.trim() : '-',
            'language': d.language.id,
            'songType': d.type.id,
            'voiceId': request.voiceId,
            'style': {
              'genre': d.genre.id,
              'mood': d.mood.id,
              'tempo': d.tempo.id,
              'duration': d.duration.id,
              'intensity': d.intensity.id,
              'instruments': d.instruments.id,
            },
            'advanced': d.advanced,
          },
        ),
      );
      final job = asObject(j['job']);
      final status = JobStatus.fromWire(str(job, 'status'));
      return GenerationReceipt(
        jobId: str(job, 'id'),
        status: status == JobStatus.queued
            ? GenerationStatus.queued
            : GenerationStatus.processing,
        creditsReserved: integer(job, 'credits'),
      );
    } on ApiException catch (e) {
      throw ServiceFailure(e.message);
    } on ConnectionFailure {
      // The request may have reached the server. Say so, and keep the key.
      throw const ServiceFailure(
        'We couldn’t confirm that your song was started. Check your '
        'connection and try again. Retrying the same request will not start a '
        'second song.',
      );
    }
  }
}

({int min, int max})? _sampleSeconds(Object? v) {
  if (v == null) return null;
  final o = asObject(v);
  return (min: integer(o, 'min'), max: integer(o, 'max'));
}

class HttpGenerationJobs implements GenerationJobs {
  const HttpGenerationJobs(this._api);

  final ApiClient _api;

  @override
  Future<GenerationJob> job(String jobId) => guard(() async {
    final j = asObject(
      await _api.get('/v1/generation/jobs/${Uri.encodeComponent(jobId)}'),
    );
    return _job(asObject(j['job']));
  });

  @override
  Future<List<GenerationJob>> recent() => guard(() async {
    final j = asObject(await _api.get('/v1/generation/jobs'));
    return [for (final v in asList(j['jobs'])) _job(asObject(v))];
  });

  @override
  Future<GenerationJob> cancel(String jobId) => guard(() async {
    final j = asObject(
      await _api.post(
        '/v1/generation/jobs/${Uri.encodeComponent(jobId)}/cancel',
      ),
    );
    return _job(asObject(j['job']));
  });

  static GenerationJob _job(Json j) {
    final status = JobStatus.fromWire(str(j, 'status'));
    if (status == null) {
      throw const ServiceFailure('DeenVoice sent a response we didn’t expect.');
    }
    return GenerationJob(
      id: str(j, 'id'),
      status: status,
      stage: str(j, 'stage'),
      title: str(j, 'title'),
      credits: integer(j, 'credits'),
      createdAt: time(j, 'createdAt'),
      completedAt: timeOrNull(j, 'completedAt'),
      failureCode: strOrNull(j, 'failureCode'),
      failureMessage: strOrNull(j, 'failureMessage'),
      songId: strOrNull(j, 'songId'),
    );
  }
}

class HttpSongLibrary implements SongLibrary {
  const HttpSongLibrary(this._api);

  final ApiClient _api;

  @override
  Future<List<SongRecord>> list() => guard(() async {
    final j = asObject(await _api.get('/v1/songs'));
    return [for (final v in asList(j['songs'])) _song(asObject(v))];
  });

  @override
  Future<SongRecord> rename(String songId, String title) => guard(() async {
    final j = asObject(
      await _api.patch(
        '/v1/songs/${Uri.encodeComponent(songId)}',
        json: {'title': title},
      ),
    );
    return _song(asObject(j['song']));
  });

  @override
  Future<void> delete(String songId) => guard(() async {
    await _api.delete('/v1/songs/${Uri.encodeComponent(songId)}');
  });

  @override
  Future<SignedAudio> audio(String songId) => guard(() async {
    final j = asObject(
      await _api.post('/v1/songs/${Uri.encodeComponent(songId)}/audio-url'),
    );
    return SignedAudio(
      url: _api.resolve(str(j, 'path')),
      expiresAt: time(j, 'expiresAt'),
    );
  });

  static SongRecord _song(Json j) {
    final ms = j['durationMs'];
    return SongRecord(
      id: str(j, 'id'),
      title: str(j, 'title'),
      lyrics: str(j, 'lyrics'),
      language: str(j, 'language'),
      provider: str(j, 'provider'),
      voiceName: strOrNull(j, 'voiceName'),
      duration: ms is num ? Duration(milliseconds: ms.round()) : null,
      createdAt: time(j, 'createdAt'),
    );
  }
}
