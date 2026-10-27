import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/session_controller.dart';
import 'package:deenvoice/data/api/session_store.dart';
import 'package:deenvoice/domain/auth/auth.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_backend.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 9);

  ProviderContainer make({SessionStore? store, FakeAuthService? auth}) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sessionStoreProvider.overrideWithValue(store ?? MemorySessionStore()),
        authServiceProvider.overrideWithValue(auth ?? FakeAuthService()),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  AuthSession stored({DateTime? expires}) => AuthSession(
    token: 't',
    userId: 'u',
    email: 'a@example.com',
    expiresAt: expires ?? DateTime.utc(2030),
  );

  test('starts signed out when nothing is stored', () async {
    final c = make();
    expect(await c.read(sessionProvider.future), isNull);
  });

  test('restores a stored session that has not expired', () async {
    final c = make(store: MemorySessionStore(stored()));
    expect((await c.read(sessionProvider.future))?.email, 'a@example.com');
  });

  test(
    'discards (and erases) an expired stored session instead of trusting it',
    () async {
      final store = MemorySessionStore(
        stored(expires: now.subtract(const Duration(seconds: 1))),
      );
      final c = make(store: store);
      expect(await c.read(sessionProvider.future), isNull);
      expect(await store.read(), isNull);
    },
  );

  test(
    'sign-in stores the session and clears the previous user\'s draft',
    () async {
      final store = MemorySessionStore();
      final c = make(store: store);
      await c.read(sessionProvider.future);
      c
          .read(songDraftProvider.notifier)
          .setTitle('Previous user\'s private title');

      await c
          .read(sessionProvider.notifier)
          .signIn('b@example.com', 'a-long-password');

      expect(c.read(sessionProvider).value?.email, 'b@example.com');
      expect((await store.read())?.email, 'b@example.com');
      expect(c.read(songDraftProvider).draft.title, isEmpty);
    },
  );

  test(
    'a failed sign-in leaves the user signed out and stores nothing',
    () async {
      final store = MemorySessionStore();
      final auth = FakeAuthService(
        failure: const ServiceFailure('Email or password is incorrect.'),
      );
      final c = make(store: store, auth: auth);
      await c.read(sessionProvider.future);
      await expectLater(
        c
            .read(sessionProvider.notifier)
            .signIn('a@example.com', 'wrong-password'),
        throwsA(isA<ServiceFailure>()),
      );
      expect(c.read(sessionProvider).value, isNull);
      expect(await store.read(), isNull);
    },
  );

  test(
    'sign-out revokes on the server, erases the stored session and the draft',
    () async {
      final store = MemorySessionStore(stored());
      final auth = FakeAuthService();
      final c = make(store: store, auth: auth);
      await c.read(sessionProvider.future);
      c.read(songDraftProvider.notifier).setTitle('private');
      c.read(songDraftProvider.notifier).setLanguage(SongLanguage.arabic);

      await c.read(sessionProvider.notifier).signOut();

      expect(auth.signOuts, 1);
      expect(c.read(sessionProvider).value, isNull);
      expect(await store.read(), isNull);
      expect(c.read(songDraftProvider).draft.title, isEmpty);
    },
  );

  test(
    'when the server rejects the session the user is signed out locally',
    () async {
      final store = MemorySessionStore(stored());
      final c = make(store: store);
      await c.read(sessionProvider.future);
      await c.read(sessionProvider.notifier).expire();
      expect(c.read(sessionProvider).value, isNull);
      expect(await store.read(), isNull);
    },
  );

  test('without a backend there is nothing to sign in to', () async {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [sessionStoreProvider.overrideWithValue(MemorySessionStore())],
    );
    addTearDown(c.dispose);
    await c.read(sessionProvider.future);
    await expectLater(
      c
          .read(sessionProvider.notifier)
          .signIn('a@example.com', 'a-long-password'),
      throwsA(isA<ServiceNotConfigured>()),
    );
  });
}
