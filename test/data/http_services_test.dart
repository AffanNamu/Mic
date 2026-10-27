import 'dart:convert';
import 'dart:typed_data';

import 'package:deenvoice/data/api/api_client.dart';
import 'package:deenvoice/data/api/http_services.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/generation/generation_request.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records requests and answers from a route table. This is a fake of the
/// DeenVoice backend's HTTP surface for client tests; it proves the client's
/// request shapes and parsing, not the backend (which has its own suite).
class Backend {
  final requests = <http.Request>[];
  final routes = <String, http.Response Function(http.Request)>{};

  ApiClient api({String? token = 'tok'}) => ApiClient(
    baseUrl: Uri.parse('https://api.example.test'),
    token: token,
    client: MockClient((r) async {
      requests.add(r);
      final route = routes['${r.method} ${r.url.path}'];
      if (route == null) {
        return http.Response(
          '{"error":{"code":"x","message":"no route"}}',
          404,
        );
      }
      return route(r);
    }),
  );

  http.Response ok(Object body, [int status = 200]) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  late Backend be;
  setUp(() => be = Backend());

  group('account deletion', () {
    HttpAccountService service({void Function()? onUnauthorized}) {
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.example.test'),
        token: 'tok',
        onUnauthorized: onUnauthorized,
        client: MockClient((r) async {
          be.requests.add(r);
          final route = be.routes['${r.method} ${r.url.path}'];
          return route == null
              ? http.Response(
                  '{"error":{"code":"x","message":"no route"}}',
                  404,
                )
              : route(r);
        }),
      );
      return HttpAccountService(api);
    }

    test('sends the password in a DELETE body and reads the result', () async {
      be.routes['DELETE /v1/me'] = (r) => be.ok({
        'deleted': true,
        'voicesDeleted': 2,
        'songsDeleted': 3,
        'providerDeletion': 'unsupported',
        'disclosure': 'Your account was deleted.',
        'kept': ['A record of credits.', 'A record of consent.'],
      });
      final result = await service().deleteAccount(password: 'my password');
      final request = be.requests.single;
      expect(request.method, 'DELETE');
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(request.body), {'password': 'my password'});
      expect(result.voicesDeleted, 2);
      expect(result.songsDeleted, 3);
      expect(result.disclosure, 'Your account was deleted.');
      expect(result.kept, ['A record of credits.', 'A record of consent.']);
    });

    test(
      'a wrong password is shown as the server says it and does not sign out',
      () async {
        var signedOut = false;
        be.routes['DELETE /v1/me'] = (r) => be.ok({
          'error': {
            'code': 'password_incorrect',
            'message': 'That password isn’t right.',
          },
        }, 403);
        await expectLater(
          service(onUnauthorized: () => signedOut = true)
              .deleteAccount(password: 'x'),
          throwsA(
            isA<ServiceFailure>().having(
              (e) => e.message,
              'message',
              'That password isn’t right.',
            ),
          ),
        );
        expect(
          signedOut,
          isFalse,
          reason: 'a 403 is "no", not "your session ended"',
        );
      },
    );

    test('a song still being made is explained', () async {
      be.routes['DELETE /v1/me'] = (r) => be.ok({
        'error': {
          'code': 'account_busy',
          'message': 'A song is still being made.',
        },
      }, 409);
      await expectLater(
        service().deleteAccount(password: 'x'),
        throwsA(
          isA<ServiceFailure>().having(
            (e) => e.message,
            'message',
            'A song is still being made.',
          ),
        ),
      );
    });

    test('a session the server no longer accepts signs the user out', () async {
      var signedOut = false;
      be.routes['DELETE /v1/me'] = (r) => be.ok({
        'error': {'code': 'unauthorized', 'message': 'Sign in required.'},
      }, 401);
      await expectLater(
        service(onUnauthorized: () => signedOut = true)
            .deleteAccount(password: 'x'),
        throwsA(isA<SessionExpired>()),
      );
      expect(signedOut, isTrue);
    });

    test(
      'a response that is not the expected shape is a clear failure',
      () async {
        be.routes['DELETE /v1/me'] = (r) => be.ok({'deleted': true});
        await expectLater(
          service().deleteAccount(password: 'x'),
          throwsA(isA<ServiceFailure>()),
        );
      },
    );
  });

  group('capabilities mapping', () {
    test('maps only ids this app knows and reports an unavailable engine truthfully', () async {
      be.routes['GET /v1/generation/capabilities'] = (_) => be.ok({
        'engineName': 'Mureka',
        'songTypes': ['full_song', 'quantum_song'],
        'languages': ['english', 'klingon'],
        'voiceConditioning': true,
        'advancedOptionIds': <String>[],
        'available': false,
      });
      final c = await HttpSongGenerationService(be.api()).capabilities();
      expect(c.songTypes, {SongType.fullSong});
      expect(c.languages, {SongLanguage.english});
      expect(c.voiceConditioning, isTrue);
      expect(c.isAvailable, isFalse);
      expect(c.unavailableReason, contains('temporarily unavailable'));
    });

    test('no engine on the server means no capabilities at all', () async {
      be.routes['GET /v1/generation/capabilities'] = (_) => be.ok({
        'engineName': null,
        'songTypes': <String>[],
        'languages': <String>[],
        'voiceConditioning': false,
        'advancedOptionIds': <String>[],
        'available': false,
      });
      final c = await HttpSongGenerationService(be.api()).capabilities();
      expect(c.isAvailable, isFalse);
      expect(c.songTypes, isEmpty);
    });
  });

  group('submit', () {
    final draft = const SongDraft(
      title: '  Ya Rabbi ',
      lyrics: ' La ilaha illallah ',
      language: SongLanguage.english,
      genre: SongGenre.englishNasheed,
    );
    final request = GenerationRequest(
      draft: draft,
      voiceId: 'v1',
      estimatedCredits: 1,
      idempotencyKey: 'abcdef123456',
    );

    test('sends the idempotency key, trimmed text and wire ids; returns the server\'s receipt', () async {
      be.routes['POST /v1/generation/jobs'] = (_) => be.ok({
        'job': {'id': 'job-9', 'status': 'queued', 'credits': 1},
        'deduplicated': false,
      }, 202);
      final receipt = await HttpSongGenerationService(be.api()).submit(request);
      expect(receipt.jobId, 'job-9');
      expect(receipt.status, GenerationStatus.queued);
      expect(receipt.creditsReserved, 1);
      final body = jsonDecode(be.requests.single.body) as Map<String, Object?>;
      expect(body['idempotencyKey'], 'abcdef123456');
      expect(body['title'], 'Ya Rabbi');
      expect(body['lyrics'], 'La ilaha illallah');
      expect(body['language'], 'english');
      expect(body['songType'], 'full_song');
      expect(body['voiceId'], 'v1');
      expect((body['style']! as Map)['genre'], 'english_nasheed');
    });

    test('a job already past "queued" is reported as processing, from the server\'s own state', () async {
      be.routes['POST /v1/generation/jobs'] = (_) => be.ok({
        'job': {'id': 'job-9', 'status': 'processing', 'credits': 1},
        'deduplicated': true,
      });
      final receipt = await HttpSongGenerationService(be.api()).submit(request);
      expect(receipt.status, GenerationStatus.processing);
    });

    test('server refusals surface the server\'s message (e.g. unsupported language, no credits)', () async {
      be.routes['POST /v1/generation/jobs'] = (_) => be.ok({
        'error': {
          'code': 'unsupported_language',
          'message': 'Mureka does not support hausa lyrics.',
        },
      }, 422);
      await expectLater(
        HttpSongGenerationService(be.api()).submit(request),
        throwsA(
          isA<ServiceFailure>().having(
            (e) => e.message,
            'message',
            'Mureka does not support hausa lyrics.',
          ),
        ),
      );
    });

    test(
      'a lost connection says the outcome is unknown and that retrying is safe',
      () async {
        final api = ApiClient(
          baseUrl: Uri.parse('https://api.example.test'),
          client: MockClient((_) async => throw http.ClientException('reset')),
        );
        await expectLater(
          HttpSongGenerationService(api).submit(request),
          throwsA(
            isA<ServiceFailure>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('couldn’t confirm'),
                contains('will not start a second song'),
              ),
            ),
          ),
        );
      },
    );

    test('a garbled response is a failure, never a made-up receipt', () async {
      be.routes['POST /v1/generation/jobs'] = (_) => be.ok({
        'job': {'status': 'queued'},
      });
      await expectLater(
        HttpSongGenerationService(be.api()).submit(request),
        throwsA(isA<ServiceFailure>()),
      );
    });
  });

  group('voices', () {
    final consent = VoiceConsent(
      ownership: VoiceOwnership.authorizedByOwner,
      acceptedAt: DateTime.utc(2026, 10, 26),
      statementVersion: 'v1',
      authorizedBy: 'Aisha Bello',
    );
    VoiceEnrollment enrollment({VoiceConsent? c}) => VoiceEnrollment(
      displayName: 'Aisha',
      fileName: 'sample.WAV',
      audio: Uint8List.fromList([1, 2, 3]),
      consent: c ?? consent,
    );

    test(
      'creates the voice with the consent version, then uploads the recording',
      () async {
        be.routes['POST /v1/voices'] = (_) => be.ok({
          'voice': {
            'id': 'vv',
            'displayName': 'Aisha',
            'ownership': 'authorized',
            'status': 'awaiting_audio',
            'supportsSinging': false,
          },
        }, 201);
        be.routes['PUT /v1/voices/vv/audio'] = (_) => be.ok({
          'voice': {
            'id': 'vv',
            'displayName': 'Aisha',
            'ownership': 'authorized',
            'status': 'enrolling',
            'supportsSinging': false,
          },
        });
        final profile = await HttpVoiceRepository(be.api())
            .enrollVoice(enrollment());
        expect(profile.status, VoiceStatus.enrolling);
        expect(profile.kind, VoiceKind.authorized);
        final create = jsonDecode(be.requests[0].body) as Map<String, Object?>;
        expect(create['ownership'], 'authorized');
        expect(create['authorizedBy'], 'Aisha Bello');
        expect(create['consent'], {'accepted': true, 'version': 'v1'});
        expect(be.requests[1].headers['Content-Type'], 'audio/wav');
        expect(be.requests[1].bodyBytes, [1, 2, 3]);
      },
    );

    test(
      'without the server\'s consent version nothing is sent at all',
      () async {
        final c = VoiceConsent(
          ownership: VoiceOwnership.ownVoice,
          acceptedAt: DateTime.utc(2026),
        );
        await expectLater(
          HttpVoiceRepository(be.api()).enrollVoice(enrollment(c: c)),
          throwsA(isA<ServiceFailure>()),
        );
        expect(be.requests, isEmpty);
      },
    );

    test(
      'a rejected recording removes the consented-but-empty voice record again',
      () async {
        be.routes['POST /v1/voices'] = (_) => be.ok({
          'voice': {
            'id': 'vv',
            'displayName': 'Aisha',
            'ownership': 'authorized',
            'status': 'awaiting_audio',
            'supportsSinging': false,
          },
        }, 201);
        be.routes['PUT /v1/voices/vv/audio'] = (_) => be.ok({
          'error': {
            'code': 'sample_length',
            'message':
                'Provide a clear, solo recording between 5 and 15 seconds.',
          },
        }, 422);
        be.routes['DELETE /v1/voices/vv'] = (_) => be.ok({'disclosure': 'x'});
        await expectLater(
          HttpVoiceRepository(be.api()).enrollVoice(enrollment()),
          throwsA(
            isA<ServiceFailure>().having(
              (e) => e.message,
              'message',
              contains('between 5 and 15 seconds'),
            ),
          ),
        );
        expect(be.requests.last.method, 'DELETE');
      },
    );

    test('maps server states honestly: failed voices keep the server\'s reason; waiting-for-audio is not "ready"', () async {
      be.routes['GET /v1/voices'] = (_) => be.ok({
        'voices': [
          {
            'id': '1',
            'displayName': 'A',
            'ownership': 'own',
            'status': 'ready',
            'supportsSinging': true,
          },
          {
            'id': '2',
            'displayName': 'B',
            'ownership': 'own',
            'status': 'failed',
            'supportsSinging': false,
            'failureMessage': 'Try a clearer solo recording.',
          },
          {
            'id': '3',
            'displayName': 'C',
            'ownership': 'own',
            'status': 'awaiting_audio',
            'supportsSinging': false,
          },
          {
            'id': '4',
            'displayName': 'D',
            'ownership': 'authorized',
            'status': 'revoked',
            'supportsSinging': true,
          },
        ],
      });
      final v = await HttpVoiceRepository(be.api()).listVoices();
      expect(v.map((x) => x.status), [
        VoiceStatus.ready,
        VoiceStatus.failed,
        VoiceStatus.failed,
        VoiceStatus.revoked,
      ]);
      expect(v[0].isSelectable, isTrue);
      expect(v[1].detail, 'Try a clearer solo recording.');
      expect(v[2].isSelectable, isFalse);
      expect(v[3].isSelectable, isFalse);
    });

    test(
      'delete returns the server\'s disclosure about what the provider keeps',
      () async {
        be.routes['DELETE /v1/voices/vv'] = (_) => be.ok({
          'voiceId': 'vv',
          'disclosure':
              'The music provider could not delete its copy automatically.',
        });
        final text = await HttpVoiceRepository(be.api()).deleteVoice('vv');
        expect(text, contains('could not delete its copy'));
      },
    );
  });

  group('credits, jobs, library', () {
    test('balance is the available amount only', () async {
      be.routes['GET /v1/credits'] = (_) => be.ok({'available': 7, 'held': 2});
      expect(await HttpCreditsRepository(be.api()).balance(), 7);
    });

    test('jobs carry the server\'s stage and failure wording as-is', () async {
      be.routes['GET /v1/generation/jobs/j1'] = (_) => be.ok({
        'job': {
          'id': 'j1',
          'status': 'failed',
          'stage': 'Failed',
          'title': 'T',
          'credits': 1,
          'failureCode': 'timeout',
          'failureMessage': 'This song took too long and was stopped. Your credits were returned.',
          'songId': null,
          'createdAt': '2026-10-26T09:00:00.000Z',
          'updatedAt': '2026-10-26T09:20:00.000Z',
          'completedAt': '2026-10-26T09:20:00.000Z',
        },
      });
      final j = await HttpGenerationJobs(be.api()).job('j1');
      expect(j.status, JobStatus.failed);
      expect(j.failureMessage, contains('credits were returned'));
      expect(j.status.isFinished, isTrue);
    });

    test('an unknown job status is rejected rather than guessed', () async {
      be.routes['GET /v1/generation/jobs/j1'] = (_) => be.ok({
        'job': {
          'id': 'j1',
          'status': 'teleporting',
          'stage': 's',
          'title': 'T',
          'credits': 1,
          'createdAt': '2026-10-26T09:00:00.000Z',
        },
      });
      await expectLater(
        HttpGenerationJobs(be.api()).job('j1'),
        throwsA(isA<ServiceFailure>()),
      );
    });

    test(
      'songs map, and the audio link is resolved against the API base',
      () async {
        be.routes['GET /v1/songs'] = (_) => be.ok({
          'songs': [
            {
              'id': 's1',
              'title': 'Song',
              'lyrics': 'words',
              'language': 'english',
              'voiceName': 'Aisha',
              'provider': 'mureka',
              'durationMs': 183400,
              'audioMime': 'audio/mpeg',
              'audioBytes': 1,
              'createdAt': '2026-10-26T09:00:00.000Z',
            },
          ],
        });
        be.routes['POST /v1/songs/s1/audio-url'] = (_) => be.ok({
          'path': '/media/songs/s1?exp=1&sig=abc',
          'expiresAt': '2026-10-26T09:05:00.000Z',
        });
        final lib = HttpSongLibrary(be.api());
        final songs = await lib.list();
        expect(songs.single.duration, const Duration(milliseconds: 183400));
        expect(songs.single.provider, 'mureka');
        final audio = await lib.audio('s1');
        expect(
          audio.url.toString(),
          'https://api.example.test/media/songs/s1?exp=1&sig=abc',
        );
      },
    );
  });

  group('auth', () {
    test('sign-in returns the session and sends no token', () async {
      be.routes['POST /v1/auth/login'] = (_) => be.ok({
        'userId': 'u1',
        'email': 'a@example.com',
        'token': 'secret-token',
        'expiresAt': '2026-11-25T09:00:00.000Z',
      });
      final s = await HttpAuthService(be.api(token: 'stale'))
          .signIn(email: ' a@example.com ', password: 'pw-pw-pw-pw');
      expect(s.token, 'secret-token');
      expect(be.requests.single.headers.containsKey('Authorization'), isFalse);
      expect(
        (jsonDecode(be.requests.single.body) as Map)['email'],
        'a@example.com',
      );
    });

    test('wrong credentials show the server\'s message', () async {
      be.routes['POST /v1/auth/login'] = (_) => be.ok({
        'error': {
          'code': 'invalid_credentials',
          'message': 'Email or password is incorrect.',
        },
      }, 401);
      await expectLater(
        HttpAuthService(be.api())
            .signIn(email: 'a@example.com', password: 'nope-nope-nope'),
        throwsA(
          isA<ServiceFailure>().having(
            (e) => e.message,
            'message',
            'Email or password is incorrect.',
          ),
        ),
      );
    });

    test('sign-out never throws even if the server is unreachable', () async {
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.example.test'),
        token: 't',
        client: MockClient((_) async => throw http.ClientException('down')),
      );
      await HttpAuthService(api).signOut();
    });
  });
}
