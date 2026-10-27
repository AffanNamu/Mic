// The My Voice and Library tabs.
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_helpers.dart';
import '../support/screen_rig.dart';

void main() {
  setUpAll(loadAppFonts);

  group('My Voice', () {
    testWidgets('lists the user\'s voices with what each is', (tester) async {
      await pumpScreens(
        tester,
        signedIn: true,
        voices: const [readyOwnVoice, readyAuthorizedVoice],
      );
      await openTab(tester, 'My Voice');
      expect(find.text('Your voice · Personal voice'), findsOneWidget);
      expect(find.text('Authorized voice · Female voice'), findsOneWidget);
      expect(
        find.textContaining(
          'Only your own voice, or the voice of someone who has agreed',
        ),
        findsOneWidget,
      );
    });

    testWidgets('with no voices it says so and offers to add one', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true, voices: const []);
      await openTab(tester, 'My Voice');
      expect(
        find.textContaining('You have no saved voices yet'),
        findsOneWidget,
      );
      await tapAndSettle(
        tester,
        find.widgetWithText(FilledButton, 'Add New Voice'),
      );
      expect(find.text(FakeConsentSource.own), findsOneWidget);
    });

    testWidgets(
      'Add New Voice opens the consent sheet with the server\'s wording',
      (tester) async {
        await pumpScreens(tester, signedIn: true);
        await openTab(tester, 'My Voice');
        await tapAndSettle(tester, find.text('Add New Voice'));
        expect(find.text(FakeConsentSource.own), findsOneWidget);
        expect(find.text('Record now'), findsOneWidget);
        expect(find.text('Upload a recording'), findsOneWidget);
      },
    );

    testWidgets(
      'deleting a voice asks first and the tab then shows the change',
      (tester) async {
        final repo = FakeVoiceRepository(const [
          readyOwnVoice,
          readyAuthorizedVoice,
        ]);
        await pumpScreens(tester, signedIn: true, voiceRepo: repo);
        await openTab(tester, 'My Voice');
        await tapAndSettle(tester, find.byTooltip('Delete Sister Aisha'));
        expect(find.text('Delete Sister Aisha?'), findsOneWidget);
        await tapAndSettle(tester, find.text('Cancel'));
        expect(repo.voices, hasLength(2));

        await tapAndSettle(tester, find.byTooltip('Delete Sister Aisha'));
        await tapAndSettle(tester, find.text('Delete').last);
        expect(repo.voices.map((v) => v.id), ['voice-own']);
        expect(find.text('Authorized voice · Female voice'), findsNothing);
      },
    );

    testWidgets(
      'a voice deleted here is gone from Create Song after going back',
      (tester) async {
        // The same list feeds Create Song; it must not show a deleted voice, nor
        // throw while the screens underneath are woken.
        final repo = FakeVoiceRepository(const [
          readyOwnVoice,
          readyAuthorizedVoice,
        ]);
        await pumpScreens(tester, signedIn: true, voiceRepo: repo);
        await openTab(tester, 'My Voice');
        await tapAndSettle(tester, find.byTooltip('Delete Sister Aisha'));
        await tapAndSettle(tester, find.text('Delete').last);
        await openTab(tester, 'Home');
        await openCreateFromHome(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('Sister Aisha'), findsNothing);
      },
    );

    testWidgets('a voice that cannot be loaded says so and can retry', (
      tester,
    ) async {
      final repo = FakeVoiceRepository(const [readyOwnVoice])
        ..listFailure = const ServiceFailure('Voices are unavailable.');
      await pumpScreens(tester, signedIn: true, voiceRepo: repo);
      await openTab(tester, 'My Voice');
      expect(find.text('Voices are unavailable.'), findsOneWidget);
      repo.listFailure = null;
      await tapAndSettle(tester, find.text('Retry'));
      expect(find.text('Your voice · Personal voice'), findsOneWidget);
    });
  });

  group('Library', () {
    testWidgets('lists songs, songs being made and songs that failed', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: true,
        songs: [song(title: 'Ya Rabbi')],
        jobs: [
          job(
            JobStatus.processing,
            id: 'p',
            title: 'Being made',
            stage: 'Generating your song',
          ),
          GenerationJob(
            id: 'f',
            status: JobStatus.failed,
            stage: 'Failed',
            title: 'Did not work',
            credits: 1,
            createdAt: screenNow.subtract(const Duration(hours: 1)),
            failureMessage: 'The music service returned no audio. Your credit was returned.',
          ),
        ],
      );
      await openTab(tester, 'Library');
      expect(find.text('My Library'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('Generating your song'), findsOneWidget);
      expect(find.text('Couldn’t be made'), findsOneWidget);
      expect(find.textContaining('Your credit was returned'), findsOneWidget);
      expect(find.text('Your songs'), findsOneWidget);
      expect(find.text('Ya Rabbi'), findsOneWidget);
    });

    testWidgets('has the credits pill, which opens the credits sheet', (
      tester,
    ) async {
      await pumpScreens(tester, signedIn: true);
      await openTab(tester, 'Library');
      expect(find.textContaining('120'), findsOneWidget);
      await tapAndSettle(tester, find.textContaining('120'));
      expect(find.text('120 credits available'), findsOneWidget);
    });

    testWidgets('without a backend it says nothing can be saved', (
      tester,
    ) async {
      await pumpProductionApp(tester, openCreate: false);
      await openTab(tester, 'Library');
      expect(
        find.textContaining('isn’t connected to a DeenVoice service'),
        findsOneWidget,
      );
    });

    testWidgets('a song that is deleted disappears from Home too', (
      tester,
    ) async {
      final lib = FakeSongLibrary([song(id: 'a', title: 'Ya Rabbi')]);
      await pumpScreens(tester, signedIn: true, library: lib);
      expect(find.text('Ya Rabbi'), findsOneWidget);
      await openTab(tester, 'Library');
      await tapAndSettle(tester, find.text('Ya Rabbi'));
      await tapAndSettle(tester, find.byTooltip('Delete'));
      await tapAndSettle(tester, find.text('Delete').last);
      expect(lib.songs, isEmpty);
      await openTab(tester, 'Home');
      expect(find.text('Ya Rabbi'), findsNothing);
      expect(find.textContaining('No songs yet'), findsOneWidget);
    });
  });
}
