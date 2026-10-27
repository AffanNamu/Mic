import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth/auth.dart';
import '../domain/failures.dart';
import 'providers.dart';

/// The signed-in user, restored from storage at launch. `null` data means
/// signed out. An expired stored session is discarded rather than trusted.
final sessionProvider = AsyncNotifierProvider<SessionController, AuthSession?>(
  SessionController.new,
);

class SessionController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() async {
    final store = ref.read(sessionStoreProvider);
    final stored = await store.read();
    if (stored == null) return null;
    if (stored.isExpired(ref.read(clockProvider)())) {
      await store.clear();
      return null;
    }
    return stored;
  }

  Future<void> signIn(String email, String password) =>
      _open((auth) => auth.signIn(email: email, password: password));

  Future<void> register(String email, String password) =>
      _open((auth) => auth.register(email: email, password: password));

  Future<void> _open(Future<AuthSession> Function(AuthService) action) async {
    final auth = ref.read(authServiceProvider);
    if (auth == null) throw const ServiceNotConfigured('Sign-in');
    final session = await action(auth);
    await ref.read(sessionStoreProvider).write(session);
    _resetUserData();
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    final auth = ref.read(authServiceProvider);
    if (auth != null) await auth.signOut();
    await _forget();
  }

  /// The server no longer accepts the session. Called by the API client.
  Future<void> expire() => _forget();

  Future<void> _forget() async {
    await ref.read(sessionStoreProvider).clear();
    _resetUserData();
    state = const AsyncData(null);
  }

  /// Nothing one user typed or loaded may be visible to the next.
  void _resetUserData() {
    ref.invalidate(songDraftProvider);
    ref.invalidate(voicesProvider);
    ref.invalidate(creditBalanceProvider);
    ref.invalidate(capabilitiesProvider);
    ref.invalidate(songsProvider);
    ref.invalidate(recentJobsProvider);
  }
}
