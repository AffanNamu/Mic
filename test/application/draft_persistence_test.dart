import 'dart:async';

import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/session_controller.dart';
import 'package:deenvoice/data/api/session_store.dart';
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/auth/auth.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_template.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_backend.dart';
import '../support/harness.dart';

/// A store whose first read waits until the test says so.
class _SlowStore extends MemoryDraftStore {
  _SlowStore(super.saved);

  final gate = Completer<void>();

  @override
  Future<SavedDraft?> read() async {
    await gate.future;
    return saved;
  }
}

AuthSession _session(String id) => AuthSession(
  token: 't-$id',
  userId: id,
  email: '$id@example.com',
  expiresAt: DateTime.utc(2030),
);

final _t0 = DateTime.utc(2026, 10, 27, 8);

void main() {
  late MemoryDraftStore drafts;

  /// A container, optionally with a backend and a signed-in user.
  ProviderContainer make({
    DraftStore? store,
    String? signedInAs,
    bool backend = false,
  }) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        ...localStoreOverrides(drafts: store ?? drafts),
        clockProvider.overrideWithValue(() => _t0),
        if (backend || signedInAs != null)
          apiBaseUrlProvider.overrideWithValue('https://api.example.test'),
        sessionStoreProvider.overrideWithValue(
          MemorySessionStore(signedInAs == null ? null : _session(signedInAs)),
        ),
        authServiceProvider.overrideWithValue(FakeAuthService()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => drafts = MemoryDraftStore());

  Future<void> pass(WidgetTester tester, [int ms = 700]) async {
    await tester.pump(Duration(milliseconds: ms));
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('saving', () {
    testWidgets('writing is delayed, then the draft is stored with its owner', (
      tester,
    ) async {
      final c = make();
      final n = c.read(songDraftProvider.notifier);
      await pass(tester, 10);
      n.setTitle('Ya Rabbi');
      n.setLyrics('Allahu Allah');
      await pass(tester, 300);
      expect(drafts.writes, 0, reason: 'debounced');
      await pass(tester, 400);
      expect(drafts.writes, 1);
      expect(drafts.saved!.draft.title, 'Ya Rabbi');
      expect(drafts.saved!.draft.lyrics, 'Allahu Allah');
      expect(drafts.saved!.savedAt, _t0);
      expect(drafts.saved!.ownerId, isNull);
    });

    testWidgets('a draft with nothing written is not kept', (tester) async {
      drafts.saved = SavedDraft(
        draft: const SongDraft(title: 'Old'),
        savedAt: _t0,
        ownerId: null,
      );
      final c = make();
      final n = c.read(songDraftProvider.notifier);
      await pass(tester, 10);
      n.setTitle('');
      n.setLanguage(SongLanguage.english);
      await pass(tester);
      expect(drafts.saved, isNull);
    });

    testWidgets('a signed-in user\'s draft is stored under their id', (
      tester,
    ) async {
      final c = make(signedInAs: 'u1');
      await c.read(sessionProvider.future);
      c.read(songDraftProvider.notifier).setTitle('Mine');
      await pass(tester);
      expect(drafts.saved!.ownerId, 'u1');
    });

    testWidgets('nothing is saved when signed out of a backend build', (
      tester,
    ) async {
      final c = make(backend: true);
      await c.read(sessionProvider.future);
      c.read(songDraftProvider.notifier).setTitle('Nobody\'s');
      await pass(tester);
      expect(drafts.saved, isNull);
    });

    testWidgets('lyrics replaced from an import are saved too', (tester) async {
      final c = make();
      c.read(songDraftProvider.notifier).replaceLyrics('imported words');
      await pass(tester);
      expect(drafts.saved!.draft.lyrics, 'imported words');
    });
  });

  group('restoring', () {
    testWidgets('the draft comes back after a restart, with its edit time', (
      tester,
    ) async {
      drafts.saved = SavedDraft(
        draft: const SongDraft(title: 'Ya Rabbi', lyrics: 'words'),
        savedAt: DateTime.utc(2026, 10, 27, 6),
        ownerId: null,
      );
      final c = make();
      c.listen(songDraftProvider, (_, _) {});
      await pass(tester, 10);
      final s = c.read(songDraftProvider);
      expect(s.draft.title, 'Ya Rabbi');
      expect(s.editedAt, DateTime.utc(2026, 10, 27, 6));
    });

    testWidgets('what the user typed meanwhile is never overwritten', (
      tester,
    ) async {
      final store = _SlowStore(
        SavedDraft(
          draft: const SongDraft(title: 'From disk'),
          savedAt: _t0,
          ownerId: null,
        ),
      );
      final c = make(store: store);
      c.listen(songDraftProvider, (_, _) {});
      await pass(tester, 10);
      c.read(songDraftProvider.notifier).setTitle('Typed first');
      store.gate.complete();
      await pass(tester, 10);
      expect(c.read(songDraftProvider).draft.title, 'Typed first');
      await pass(tester); // let the debounced save run before the test ends
    });

    testWidgets(
      'a draft saved for someone else is never shown, and is erased',
      (tester) async {
        drafts.saved = SavedDraft(
          draft: const SongDraft(title: 'Private to u1'),
          savedAt: _t0,
          ownerId: 'u1',
        );
        final c = make(signedInAs: 'u2');
        c.listen(songDraftProvider, (_, _) {});
        await c.read(sessionProvider.future);
        await pass(tester, 10);
        expect(c.read(songDraftProvider).draft.title, isEmpty);
        expect(drafts.saved, isNull);
      },
    );

    testWidgets('nothing is restored while signed out of a backend build', (
      tester,
    ) async {
      drafts.saved = SavedDraft(
        draft: const SongDraft(title: 'Private'),
        savedAt: _t0,
        ownerId: 'u1',
      );
      final c = make(backend: true);
      c.listen(songDraftProvider, (_, _) {});
      await c.read(sessionProvider.future);
      await pass(tester, 10);
      expect(c.read(songDraftProvider).draft.title, isEmpty);
      expect(drafts.saved, isNull);
    });

    testWidgets('the owner\'s own draft is restored', (tester) async {
      drafts.saved = SavedDraft(
        draft: const SongDraft(title: 'Mine'),
        savedAt: _t0,
        ownerId: 'u1',
      );
      final c = make(signedInAs: 'u1');
      c.listen(songDraftProvider, (_, _) {});
      await c.read(sessionProvider.future);
      await pass(tester, 10);
      expect(c.read(songDraftProvider).draft.title, 'Mine');
    });
  });

  group('leaving', () {
    testWidgets('discard empties the draft here and on disk', (tester) async {
      final c = make();
      final n = c.read(songDraftProvider.notifier);
      n.setTitle('x');
      await pass(tester);
      expect(drafts.saved, isNotNull);
      n.discard();
      await pass(tester, 10);
      expect(c.read(songDraftProvider).draft.title, isEmpty);
      expect(c.read(songDraftProvider).editedAt, isNull);
      expect(drafts.saved, isNull);
    });

    testWidgets(
      'a discard right after typing is not undone by the pending save',
      (tester) async {
        final c = make();
        final n = c.read(songDraftProvider.notifier);
        n.setTitle('typed');
        n.discard();
        await pass(tester);
        expect(drafts.saved, isNull);
      },
    );

    testWidgets('signing out erases the saved draft and activity marker', (
      tester,
    ) async {
      final activity = MemoryActivityStore();
      await activity.markSeen('u1', _t0);
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...localStoreOverrides(drafts: drafts, activity: activity),
          apiBaseUrlProvider.overrideWithValue('https://api.example.test'),
          sessionStoreProvider.overrideWithValue(
            MemorySessionStore(_session('u1')),
          ),
          authServiceProvider.overrideWithValue(FakeAuthService()),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sessionProvider.future);
      c.read(songDraftProvider.notifier).setTitle('private');
      await pass(tester);
      expect(drafts.saved, isNotNull);

      await c.read(sessionProvider.notifier).signOut();

      expect(drafts.saved, isNull);
      expect(await activity.lastSeen('u1'), isNull);
    });
  });

  group('templates', () {
    testWidgets('only language and style change; the user\'s words stay', (
      tester,
    ) async {
      final c = make();
      final n = c.read(songDraftProvider.notifier);
      n.setTitle('Mine');
      n.setLyrics('My words');
      n.applyTemplate(SongTemplate.arabicNasheed);
      final d = c.read(songDraftProvider).draft;
      expect(d.language, SongLanguage.arabic);
      expect(d.genre, SongGenre.arabicNasheed);
      expect(d.title, 'Mine');
      expect(d.lyrics, 'My words');
      await pass(tester);
    });

    test('names and subtitles come from the existing genre wording', () {
      expect(SongTemplate.hausaNasheed.label, 'Hausa Nasheed');
      expect(SongTemplate.hausaNasheed.subtitle, 'Traditional & modern');
      expect(SongTemplate.arabicNasheed.subtitle, 'Spiritual & uplifting');
      expect(SongTemplate.englishNasheed.subtitle, 'Modern & inspirational');
      expect(SongTemplate.mixedLanguage.label, 'Mixed Language');
      expect(SongTemplate.mixedLanguage.subtitle, 'Hausa · Arabic · English');
    });
  });
}
