import 'package:flutter/foundation.dart';

/// A signed-in user's session with the DeenVoice backend.
@immutable
class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.email,
    required this.expiresAt,
  });

  /// Opaque bearer token. Treat as a secret: never log it.
  final String token;
  final String userId;
  final String email;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !expiresAt.isAfter(now);

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.token == token &&
      other.userId == userId &&
      other.email == email &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode => Object.hash(token, userId, email, expiresAt);
}

abstract interface class AuthService {
  Future<AuthSession> register({
    required String email,
    required String password,
  });

  Future<AuthSession> signIn({required String email, required String password});

  /// Revokes the session on the server. Callers clear local state regardless.
  Future<void> signOut();
}

/// Keeps the session between launches.
abstract interface class SessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}
