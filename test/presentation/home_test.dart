// Home, and the bottom bar around it. Everything shown comes from test doubles;
// these tests prove what the app does with real data and with none.
import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_template.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:deenvoice/presentation/home/home_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/fakes.dart';
import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_helpers.dart';
import '../support/screen_rig.dart';

ProviderContainer container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(DeenVoiceApp)));

SavedDraft savedDraft({
  String title = '',
  String lyrics = 'Ya Rabbi',
  Duration age = const Duration(hours: 2),
}) => SavedDraft(
  draft: SongDraft(title: title, lyrics: lyrics),
  savedAt: screenNow.subtract(age),
  ownerId: 'u',
);

const _engineWithoutHausa = GenerationCapabilities(
  engineName: 'Test Engine',
  songTypes: {...SongType.values},
  languages: {SongLanguage.english, SongLanguage.arabic},
  voiceConditioning: true,
  advancedOptionIds: {},
);

void main() {
  setUpAll(loadAppFonts);

  group('hero and shortcuts', () {
    testWidgets('Create a Song opens Create Song; Back returns to Home', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await openCreateFromHome(tester);
      expect(find.text('Generate Song'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Back'));
      await settle(tester);
      expect(find.text('Create a Song'), findsOneWidget);
    });

    testWidgets('there is no demo video, so there is no "Watch Demo"', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      expect(find.text('Watch Demo'), findsNothing);
      expect(find.text('How it works'), findsOneWidget);
    });

    testWidgets('How it works shows the real steps, including the limits', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await tapAndSettle(tester, find.text('How it works'));
      expect(find.text('How DeenVoice works'), findsOneWidget);
      for (final step in [
        'Add your voice',
        'Write your lyrics',
        'Choose a style',
        'Generate',
      ]) {
        expect(find.text(step), findsOneWidget);
      }
      expect(find.textContaining('engine’s name on it'), findsOneWidget);
      expect(find.textContaining('the app checks first'), findsOneWidget);
    });

    testWidgets('each shortcut goes where it says', (tester) async {
      await pumpScreens(tester, signedIn: true);

      await tapAndSettle(tester, find.text('My Voice').first);
      expect(find.text('Record or upload your voice'), findsOneWidget);
      await openTab(tester, 'Home');

      await tapAndSettle(tester, find.text('My Library'));
      expect(find.text('Your songs and projects'), findsOneWidget);
      await openTab(tester, 'Home');

      await tapAndSettle(tester, find.text('Create Song'));
      expect(find.text('Generate Song'), findsWidgets);
    });

    testWidgets(
      'Write Lyrics promises only what exists and opens at the lyrics',
      (tester) async {
        await pumpScreens(tester, signedIn: true);
        expect(find.text('Get AI help\nwith lyrics'), findsNothing);
        expect(find.textContaining('Write or import'), findsOneWidget);
        await tapAndSettle(tester, find.text('Write Lyrics'));
        // Create Song opened already scrolled to the lyrics editor.
        final lyrics = tester.getRect(
          find.byKey(const ValueKey('lyrics-field')),
        );
        expect(lyrics.top, lessThan(500));
        expect(lyrics.bottom, greaterThan(0));
      },
    );
  });

  group('recent songs', () {
    testWidgets('without a backend it says so instead of showing anything', (
      tester,
    ) async {
      await pumpProductionApp(tester, openCreate: false);
      expect(find.text('Recent Songs'), findsOneWidget);
      expect(find.textContaining('isn’t connected'), findsWidgets);
      expect(find.text('See All'), findsNothing);
      expect(find.text('Ya Rabbi'), findsNothing);
    });

    testWidgets('with a backend and no songs, it says there are none', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      expect(find.textContaining('No songs yet'), findsOneWidget);
      await tapAndSettle(tester, find.text('Create').first);
      expect(find.text('Generate Song'), findsWidgets);
    });

    testWidgets('shows the user\'s real songs and opens one', (tester) async {
      await pumpScreens(
        tester,
        signedIn: true,
        songs: [
          song(id: 'a', title: 'Ya Rabbi'),
          song(
            id: 'b',
            title: 'Rabbana',
            duration: const Duration(minutes: 4, seconds: 18),
          ),
        ],
      );
      expect(find.text('Ya Rabbi'), findsOneWidget);
      expect(find.text('Rabbana'), findsOneWidget);
      expect(find.text('English · 3:05'), findsOneWidget);
      expect(find.text('English · 4:18'), findsOneWidget);
      await tapAndSettle(tester, find.text('Rabbana'));
      expect(find.textContaining('Made with Mureka'), findsOneWidget);
    });

    testWidgets('See All goes to the library', (tester) async {
      await pumpScreens(tester, signedIn: true, songs: [song()]);
      await tapAndSettle(tester, find.text('See All'));
      expect(find.text('My Library'), findsOneWidget);
      expect(find.text('Your songs'), findsOneWidget);
    });

    testWidgets(
      'a song being made shows the server\'s stage, a finished one does not',
      (tester) async {
        await pumpScreens(
          tester,
          signedIn: true,
          songs: [song(title: 'Done one')],
          jobs: [
            job(
              JobStatus.processing,
              id: 'p',
              title: 'Being made',
              stage: 'Generating your song',
            ),
            job(
              JobStatus.completed,
              id: 'c',
              title: 'Already a song',
              songId: 'song-1',
            ),
          ],
        );
        expect(find.text('Being made'), findsOneWidget);
        expect(find.text('Generating your song'), findsOneWidget);
        expect(find.text('Already a song'), findsNothing);
        expect(find.text('Done one'), findsOneWidget);
      },
    );

    testWidgets('if songs cannot be loaded it says why and can retry', (
      tester,
    ) async {
      final failing = FakeSongLibraryThatFails();
      await pumpScreens(tester, signedIn: true, library: failing);
      expect(find.text('The server is down.'), findsOneWidget);
      failing.failure = null;
      await tapAndSettle(tester, find.text('Try again'));
      expect(find.textContaining('No songs yet'), findsOneWidget);
    });

    test('a song always gets the same one of the three generic covers', () {
      expect(coverFor('song-1'), coverFor('song-1'));
      final seen = {for (var i = 0; i < 60; i++) coverFor('song-$i')};
      expect(seen.length, 3);
      for (final path in seen) {
        expect(path, startsWith('assets/art/cover_'));
      }
    });
  });

  group('quick start', () {
    testWidgets('a template sets language and style and opens Create', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await tapAndSettle(tester, find.text('Arabic Nasheed'));
      final draft = container(tester).read(songDraftProvider).draft;
      expect(draft.language, SongLanguage.arabic);
      expect(draft.genre, SongGenre.arabicNasheed);
      expect(find.text('Generate Song'), findsWidgets);
    });

    testWidgets('a template does not touch what the user wrote', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: true,
        drafts: MemoryDraftStore(savedDraft(title: 'Mine', lyrics: 'My words')),
      );
      await tapAndSettle(tester, find.text('English Nasheed'));
      final draft = container(tester).read(songDraftProvider).draft;
      expect(draft.title, 'Mine');
      expect(draft.lyrics, 'My words');
      expect(draft.language, SongLanguage.english);
    });

    testWidgets('a language the connected engine cannot sing is not offered', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: true,
        generation: FakeGenerationService(capabilities: _engineWithoutHausa),
      );
      expect(find.text('Not supported by Test Engine'), findsNWidgets(2));
      // Hausa and Mixed are refused; Arabic and English are not.
      final before = container(tester).read(songDraftProvider).draft;
      await tester.tap(find.text('Hausa Nasheed'));
      await settle(tester);
      expect(find.text('Generate Song'), findsNothing);
      expect(container(tester).read(songDraftProvider).draft, before);
      await tapAndSettle(tester, find.text('English Nasheed'));
      expect(find.text('Generate Song'), findsWidgets);
    });

    testWidgets('with no engine information every template is available', (
      tester,
    ) async {
      await pumpProductionApp(tester, openCreate: false);
      expect(find.textContaining('Not supported by'), findsNothing);
      await tapAndSettle(tester, find.text('Hausa Nasheed'));
      expect(find.text('Generate Song'), findsWidgets);
    });

    testWidgets('the template that matches the draft is marked selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreens(tester, signedIn: true);
      container(tester)
          .read(songDraftProvider.notifier)
          .applyTemplate(SongTemplate.englishNasheed);
      await settle(tester);
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^English Nasheed'))),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('^Arabic Nasheed'))),
        isSemantics(isSelected: false),
      );
      handle.dispose();
    });
  });

  group('continue your work', () {
    testWidgets('nothing is shown when there is no draft', (tester) async {
      await pumpScreens(tester, signedIn: true);
      expect(find.text('Continue Your Work'), findsNothing);
    });

    testWidgets('a draft with only default choices is not "work"', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: true,
        drafts: MemoryDraftStore(savedDraft(lyrics: '')),
      );
      expect(find.text('Continue Your Work'), findsNothing);
    });

    testWidgets('the saved draft is offered with how long ago it was edited', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: true,
        drafts: MemoryDraftStore(savedDraft()),
      );
      expect(find.text('Continue Your Work'), findsOneWidget);
      expect(find.text('Untitled Song'), findsOneWidget);
      expect(find.text('Last edited 2 hours ago'), findsOneWidget);
    });

    testWidgets(
      'a draft with a title shows it, and Continue reopens the words',
      (tester) async {
        await pumpScreens(
          tester,
          signedIn: true,
          drafts: MemoryDraftStore(
            savedDraft(title: 'Ya Rabbi', lyrics: 'Allahu Allah'),
          ),
        );
        expect(find.text('Ya Rabbi'), findsOneWidget);
        await tapAndSettle(tester, find.text('Continue'));
        expect(find.text('Allahu Allah'), findsOneWidget);
      },
    );

    testWidgets('someone else\'s draft is never shown', (tester) async {
      final other = SavedDraft(
        draft: const SongDraft(title: 'Private to someone else'),
        savedAt: screenNow,
        ownerId: 'not-u',
      );
      final store = MemoryDraftStore(other);
      await pumpScreens(tester, signedIn: true, drafts: store);
      expect(find.text('Continue Your Work'), findsNothing);
      expect(find.text('Private to someone else'), findsNothing);
      expect(store.saved, isNull);
    });

    testWidgets(
      'discarding asks first, and removes the draft from the device',
      (tester) async {
        final store = MemoryDraftStore(savedDraft());
        await pumpScreens(tester, signedIn: true, drafts: store);
        await tapAndSettle(tester, find.byTooltip('Draft options'));
        await tapAndSettle(tester, find.text('Discard draft'));
        expect(find.text('Discard this draft?'), findsOneWidget);
        await tapAndSettle(tester, find.text('Cancel'));
        expect(find.text('Continue Your Work'), findsOneWidget);
        expect(store.saved, isNotNull);

        await tapAndSettle(tester, find.byTooltip('Draft options'));
        await tapAndSettle(tester, find.text('Discard draft'));
        await tapAndSettle(tester, find.text('Discard'));
        expect(find.text('Continue Your Work'), findsNothing);
        expect(store.saved, isNull);
      },
    );

    testWidgets('typing in Create makes the draft appear on Home', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await openCreateFromHome(tester);
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'My nasheed',
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Back'));
      await settle(tester);
      expect(find.text('Continue Your Work'), findsOneWidget);
      expect(find.text('My nasheed'), findsOneWidget);
      expect(find.text('Last edited just now'), findsOneWidget);
    });
  });

  group('header', () {
    testWidgets('the avatar is the email\'s initial and opens Profile', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await openProfile(tester);
      expect(find.text('amina@example.com'), findsOneWidget);
    });

    testWidgets('with no account the avatar is a person, not a letter', (
      tester,
    ) async {
      await pumpProductionApp(tester, openCreate: false);
      expect(find.text('A'), findsNothing);
    });

    testWidgets('the bell has no dot until something has finished', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreens(
        tester,
        signedIn: true,
        jobs: [job(JobStatus.processing, id: 'p')],
      );
      expect(find.bySemanticsLabel('Activity'), findsOneWidget);
      handle.dispose();
    });

    testWidgets(
      'a finished song the user has not seen puts a count on the bell',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpScreens(
          tester,
          signedIn: true,
          jobs: [
            GenerationJob(
              id: 'c',
              status: JobStatus.completed,
              stage: 'Ready',
              title: 'Rabbana',
              credits: 1,
              createdAt: screenNow.subtract(const Duration(minutes: 9)),
              completedAt: screenNow.subtract(const Duration(minutes: 5)),
              songId: 'b',
            ),
          ],
        );
        expect(find.bySemanticsLabel('Activity, 1 new'), findsOneWidget);
        handle.dispose();
      },
    );
  });

  group('the bottom bar', () {
    testWidgets('Home is selected at first and the tabs switch', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpScreens(tester, signedIn: true);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Home')),
        isSemantics(isSelected: true),
      );
      await openTab(tester, 'Library');
      expect(find.text('My Library'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Library')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Home')),
        isSemantics(isSelected: false),
      );
      await openTab(tester, 'My Voice');
      expect(find.text('Record or upload your voice'), findsOneWidget);
      await openTab(tester, 'Home');
      expect(find.text('Create a Song'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the system Back button on another tab goes to Home first', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await openTab(tester, 'Library');
      expect(find.text('Your songs and projects'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Create a Song'), findsOneWidget);
      expect(find.text('Your songs and projects'), findsNothing);

      await openTab(tester, 'My Voice');
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Create a Song'), findsOneWidget);
    });

    testWidgets(
      'Create and + both open Create Song over the bar, and Back returns to the same tab',
      (tester) async {
        await pumpScreens(tester, signedIn: true);
        await openTab(tester, 'Library');
        await tapAndSettle(tester, find.text('Create').last);
        expect(find.text('Generate Song'), findsWidgets);
        await tester.tap(find.bySemanticsLabel('Back'));
        await settle(tester);
        expect(find.text('My Library'), findsOneWidget);

        // The centre button (the credits pill has a smaller "+" of its own).
        await tapAndSettle(
          tester,
          find.byWidgetPredicate(
            (w) => w is Icon && w.icon == LucideIcons.plus && w.size == 26,
          ),
        );
        expect(find.text('Generate Song'), findsWidgets);
      },
    );
  });
}
