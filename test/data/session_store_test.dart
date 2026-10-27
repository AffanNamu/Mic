import 'package:deenvoice/data/api/session_store.dart';
import 'package:deenvoice/domain/auth/auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final session = AuthSession(
    token: 'tok',
    userId: 'u1',
    email: 'a@example.com',
    expiresAt: DateTime.utc(2030, 1, 2, 3, 4, 5),
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips a session', () async {
    const store = PreferencesSessionStore();
    expect(await store.read(), isNull);
    await store.write(session);
    expect(await store.read(), session);
  });

  test('clear removes it', () async {
    const store = PreferencesSessionStore();
    await store.write(session);
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a corrupt entry reads as signed out instead of crashing', () async {
    SharedPreferences.setMockInitialValues({
      'deenvoice.session.v1': '{not json',
    });
    expect(await const PreferencesSessionStore().read(), isNull);
    SharedPreferences.setMockInitialValues({
      'deenvoice.session.v1': '{"token":"x"}',
    });
    expect(await const PreferencesSessionStore().read(), isNull);
  });

  test('expiry is judged against the supplied clock', () {
    expect(session.isExpired(DateTime.utc(2030, 1, 2, 3, 4, 4)), isFalse);
    expect(session.isExpired(DateTime.utc(2030, 1, 2, 3, 4, 5)), isTrue);
  });
}
