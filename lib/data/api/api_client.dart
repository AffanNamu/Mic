import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../domain/failures.dart';

/// An error response from the backend. `message` is written by the server for
/// users and is safe to show; `code` is stable for programmatic handling.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException($status, $code)';
}

typedef Json = Map<String, Object?>;

/// Minimal JSON-over-HTTP client for the DeenVoice backend. It holds no
/// secrets of its own: the bearer token is the user's session, and provider
/// credentials exist only on the server.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this._client,
    this.token,
    this.onUnauthorized,
    this.timeout = const Duration(seconds: 25),
  });

  final Uri baseUrl;
  final http.Client _client;
  final String? token;

  /// Called when the server rejects the session, so the app can sign out.
  final void Function()? onUnauthorized;
  final Duration timeout;

  Uri resolve(String path, [Map<String, String>? query]) {
    final base = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    final relative = path.startsWith('/') ? path.substring(1) : path;
    final uri = base.resolve(relative);
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Future<Object?> get(String path) => _send('GET', path);

  Future<Object?> post(String path, {Object? json}) =>
      _send('POST', path, json: json);

  Future<Object?> patch(String path, {required Object json}) =>
      _send('PATCH', path, json: json);

  Future<Object?> delete(
    String path, {
    Map<String, String>? query,
    Object? json,
  }) => _send('DELETE', path, query: query, json: json);

  Future<Object?> putBytes(
    String path,
    Uint8List bytes, {
    required String contentType,
  }) => _send('PUT', path, bytes: bytes, contentType: contentType);

  /// Requests without a session (sign-in, consent text) never trigger the
  /// "session expired" path.
  Future<Object?> getPublic(String path) => _send('GET', path, authed: false);

  Future<Object?> postPublic(String path, {Object? json}) =>
      _send('POST', path, json: json, authed: false);

  Future<Object?> _send(
    String method,
    String path, {
    Object? json,
    Uint8List? bytes,
    String? contentType,
    Map<String, String>? query,
    bool authed = true,
  }) async {
    final request = http.Request(method, resolve(path, query));
    request.headers['Accept'] = 'application/json';
    final t = token;
    if (authed && t != null) request.headers['Authorization'] = 'Bearer $t';
    if (json != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(json);
    } else if (bytes != null) {
      request.headers['Content-Type'] =
          contentType ?? 'application/octet-stream';
      request.bodyBytes = bytes;
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const ConnectionFailure();
    } on http.ClientException {
      throw const ConnectionFailure();
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.bodyBytes.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const ServiceFailure(
          'DeenVoice sent a response we couldn’t read.',
        );
      }
    }

    if (response.statusCode == 401 && authed && t != null) {
      onUnauthorized?.call();
      throw const SessionExpired();
    }
    throw _errorFrom(response);
  }

  ApiException _errorFrom(http.Response r) {
    try {
      final body = jsonDecode(utf8.decode(r.bodyBytes));
      if (body is Map && body['error'] is Map) {
        final e = body['error'] as Map;
        final message = e['message'];
        final code = e['code'];
        if (message is String && code is String) {
          return ApiException(r.statusCode, code, message);
        }
      }
    } on FormatException {
      // fall through to the generic message
    }
    return ApiException(
      r.statusCode,
      'http_${r.statusCode}',
      r.statusCode >= 500
          ? 'DeenVoice had a problem. Please try again shortly.'
          : 'The request couldn’t be completed.',
    );
  }
}
