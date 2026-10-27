import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:deenvoice/data/api/api_client.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(int status, Object body, {Map<String, String>? headers}) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json', ...?headers},
    );

ApiClient client(
  Future<http.Response> Function(http.Request) handler, {
  String? token = 'tok',
  void Function()? onUnauthorized,
  Duration timeout = const Duration(seconds: 2),
}) => ApiClient(
  baseUrl: Uri.parse('https://api.example.test/base'),
  client: MockClient(handler),
  token: token,
  onUnauthorized: onUnauthorized,
  timeout: timeout,
);

void main() {
  group('requests', () {
    test(
      'send the bearer token, JSON, and resolve under the base path',
      () async {
        late http.Request seen;
        final api = client((r) async {
          seen = r;
          return json(200, {'ok': true});
        });
        final out = await api.post('/v1/things', json: {'a': 1});
        expect(out, {'ok': true});
        expect(seen.url.toString(), 'https://api.example.test/base/v1/things');
        expect(seen.headers['Authorization'], 'Bearer tok');
        expect(seen.headers['Content-Type'], startsWith('application/json'));
        expect(jsonDecode(seen.body), {'a': 1});
      },
    );

    test('public calls never send the token', () async {
      late http.Request seen;
      final api = client((r) async {
        seen = r;
        return json(200, {});
      });
      await api.getPublic('/v1/consent-statements');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('uploads raw bytes with the given content type', () async {
      late http.Request seen;
      final api = client((r) async {
        seen = r;
        return json(200, {});
      });
      await api.putBytes(
        '/v1/voices/1/audio',
        Uint8List.fromList([1, 2, 3]),
        contentType: 'audio/wav',
      );
      expect(seen.method, 'PUT');
      expect(seen.headers['Content-Type'], 'audio/wav');
      expect(seen.bodyBytes, [1, 2, 3]);
    });

    test('a 204 is null; delete sends query parameters', () async {
      late http.Request seen;
      final api = client((r) async {
        seen = r;
        return http.Response('', 204);
      });
      expect(await api.delete('/v1/songs/1', query: {'x': 'y'}), isNull);
      expect(seen.url.query, 'x=y');
    });
  });

  group('failures are translated, never leaked', () {
    test(
      'server errors become ApiException with the server\'s user-safe message',
      () async {
        final api = client(
          (_) async => json(422, {
            'error': {
              'code': 'unsupported_language',
              'message': 'Mureka does not support hausa lyrics.',
            },
          }),
        );
        await expectLater(
          api.post('/v1/generation/jobs', json: {}),
          throwsA(
            isA<ApiException>()
                .having((e) => e.status, 'status', 422)
                .having((e) => e.code, 'code', 'unsupported_language')
                .having(
                  (e) => e.message,
                  'message',
                  'Mureka does not support hausa lyrics.',
                ),
          ),
        );
      },
    );

    test('an HTML error page gets a generic message, not the page', () async {
      final api = client(
        (_) async =>
            http.Response('<html>Bad gateway: internal-host-7</html>', 502),
      );
      await expectLater(
        api.get('/v1/credits'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            isNot(contains('internal-host')),
          ),
        ),
      );
    });

    test('401 with a session signs out and says the session expired', () async {
      var signedOut = 0;
      final api = client(
        (_) async => json(401, {
          'error': {'code': 'unauthorized', 'message': 'x'},
        }),
        onUnauthorized: () => signedOut++,
      );
      await expectLater(api.get('/v1/me'), throwsA(isA<SessionExpired>()));
      expect(signedOut, 1);
    });

    test('401 on a public call (wrong password) is an ordinary error, not a sign-out', () async {
      var signedOut = 0;
      final api = client(
        (_) async => json(401, {
          'error': {
            'code': 'invalid_credentials',
            'message': 'Email or password is incorrect.',
          },
        }),
        onUnauthorized: () => signedOut++,
      );
      await expectLater(
        api.postPublic('/v1/auth/login', json: {}),
        throwsA(isA<ApiException>()),
      );
      expect(signedOut, 0);
    });

    test('network errors and timeouts are ConnectionFailure', () async {
      await expectLater(
        client((_) async => throw http.ClientException('socket closed'))
            .get('/x'),
        throwsA(isA<ConnectionFailure>()),
      );
      await expectLater(
        client(
          (_) => Completer<http.Response>().future,
          timeout: const Duration(milliseconds: 20),
        ).get('/x'),
        throwsA(isA<ConnectionFailure>()),
      );
    });

    test('a 2xx that is not JSON is a ServiceFailure', () async {
      final api = client((_) async => http.Response('not json', 200));
      await expectLater(api.get('/x'), throwsA(isA<ServiceFailure>()));
    });
  });
}
