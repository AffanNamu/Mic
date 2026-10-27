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

/// What deleting an account did, in the server's own words.
@immutable
class AccountDeletion {
  const AccountDeletion({
    required this.voicesDeleted,
    required this.songsDeleted,
    required this.disclosure,
    required this.kept,
  });

  final int voicesDeleted;
  final int songsDeleted;

  /// What was removed, and what the music provider may still hold.
  final String disclosure;

  /// What the service keeps after deletion, and why.
  final List<String> kept;
}

abstract interface class AccountService {
  /// Deletes the signed-in account. Needs the password again, so a stolen
  /// session cannot do it. Throws a [ServiceFailure] whose message says what to
  /// do (wrong password, a song still being made).
  Future<AccountDeletion> deleteAccount({required String password});
}
