import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/auth/auth.dart';

/// Persists the session in the platform's key-value store (browser local
/// storage on web).
///
/// Known limitation: this is not secure storage. A script running in the page,
/// or someone with the device, can read the token. Before release, move to
/// platform secure storage on mobile and short-lived tokens with refresh (or
/// httpOnly cookies) on web.
class PreferencesSessionStore implements SessionStore {
  const PreferencesSessionStore();

  static const _key = 'deenvoice.session.v1';

  @override
  Future<AuthSession?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, Object?>;
      return AuthSession(
        token: j['token']! as String,
        userId: j['userId']! as String,
        email: j['email']! as String,
        expiresAt: DateTime.parse(j['expiresAt']! as String).toUtc(),
      );
    } catch (_) {
      // A corrupt or unreadable entry means "signed out", never a crash.
      return null;
    }
  }

  @override
  Future<void> write(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'token': session.token,
        'userId': session.userId,
        'email': session.email,
        'expiresAt': session.expiresAt.toIso8601String(),
      }),
    );
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// In-memory store, for tests and for runs where nothing should persist.
class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  AuthSession? _session;

  @override
  Future<AuthSession?> read() async => _session;

  @override
  Future<void> write(AuthSession session) async => _session = session;

  @override
  Future<void> clear() async => _session = null;
}
