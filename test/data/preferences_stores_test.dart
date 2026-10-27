import 'package:deenvoice/data/local/preferences_stores.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('onboarding', () {
    test('is not complete until marked, then stays complete', () async {
      const store = PreferencesOnboardingStore();
      expect(await store.isCompleted(), isFalse);
      await store.markCompleted();
      expect(await store.isCompleted(), isTrue);
      expect(await const PreferencesOnboardingStore().isCompleted(), isTrue);
    });
  });

  group('draft', () {
    final saved = SavedDraft(
      draft: const SongDraft(title: 'Ya Rabbi', lyrics: 'words'),
      savedAt: DateTime.utc(2026, 10, 27, 8, 30),
      ownerId: 'user-1',
    );

    test('round-trips the draft, its time and its owner', () async {
      const store = PreferencesDraftStore();
      expect(await store.read(), isNull);
      await store.write(saved);
      final back = (await store.read())!;
      expect(back.draft, saved.draft);
      expect(back.savedAt, saved.savedAt);
      expect(back.ownerId, 'user-1');
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('keeps "no owner" distinct from an owner', () async {
      const store = PreferencesDraftStore();
      await store.write(
        SavedDraft(draft: saved.draft, savedAt: saved.savedAt, ownerId: null),
      );
      expect((await store.read())!.ownerId, isNull);
    });

    test('corrupt or foreign data reads as nothing, never throws', () async {
      for (final raw in [
        'not json',
        '[]',
        '{"draft": 3}',
        '{"draft": {"v": 99}, "savedAt": "2026-01-01T00:00:00Z"}',
        '{"draft": {"v": 1}, "savedAt": "yesterday"}',
      ]) {
        SharedPreferences.setMockInitialValues({'deenvoice.draft.v1': raw});
        expect(await const PreferencesDraftStore().read(), isNull, reason: raw);
      }
    });
  });

  group('activity', () {
    test('is remembered per account and forgotten on clear', () async {
      const store = PreferencesActivityStore();
      final t1 = DateTime.utc(2026, 10, 27, 9);
      final t2 = DateTime.utc(2026, 10, 27, 10);
      expect(await store.lastSeen('a'), isNull);
      await store.markSeen('a', t1);
      await store.markSeen('b', t2);
      await store.markSeen(null, t2);
      expect(await store.lastSeen('a'), t1);
      expect(await store.lastSeen('b'), t2);
      expect(await store.lastSeen(null), t2);
      await store.clear();
      expect(await store.lastSeen('a'), isNull);
      expect(await store.lastSeen('b'), isNull);
      expect(await store.lastSeen(null), isNull);
    });

    test('an unreadable timestamp reads as never seen', () async {
      SharedPreferences.setMockInitialValues({
        'deenvoice.activity.seen.v1.a': 'garbage',
      });
      expect(await const PreferencesActivityStore().lastSeen('a'), isNull);
    });
  });
}
