// Screens that exist only when a backend is connected: sign-in, the song
// library, the player, job progress and server-owned consent. Services are
// test doubles; these tests prove the app's behaviour, not any backend's.
import 'dart:typed_data';

import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/session_controller.dart';
import 'package:deenvoice/data/api/session_store.dart';
import 'package:deenvoice/domain/auth/auth.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes_backend.dart';
import '../support/harness.dart';

class Rig {
  Rig({
    this.signedIn = true,
    List<SongRecord> songs = const [],
    List<VoiceProfile> voices = const [readyOwnVoice],
    FakeGenerationService? generation,
    this.statementsFailure,
  }) : library = FakeSongLibrary(songs),
       voiceRepo = FakeVoiceRepository(voices),
       generation = generation ?? FakeGenerationService(),
       store = MemorySessionStore(
         signedIn
             ? AuthSession(
                 token: 't',
                 userId: 'u',
                 email: 'amina@example.com',
                 expiresAt: DateTime.utc(2030),
               )
             : null,
       );

  final bool signedIn;
  final FakeSongLibrary library;
  final FakeVoiceRepository voiceRepo;
  final FakeGenerationService generation;
  final MemorySessionStore store;
  final auth = FakeAuthService();
  final jobs = FakeGenerationJobs();
  final player = FakeAudioPlayer();
  final consent = FakeConsentSource();
  final AppFailure? statementsFailure;
  final audioPicker = FakeAudioFilePicker(
    PickedAudio(fileName: 'me.wav', bytes: Uint8List.fromList([1, 2, 3, 4])),
  );
  int credits = 5;

  List<Override> get overrides => [
    apiBaseUrlProvider.overrideWithValue('https://api.example.test'),
    sessionStoreProvider.overrideWithValue(store),
    authServiceProvider.overrideWithValue(auth),
    voiceRepositoryProvider.overrideWithValue(voiceRepo),
    creditsRepositoryProvider.overrideWith(
      (ref) => FakeCreditsRepository(credits),
    ),
    songGenerationServiceProvider.overrideWithValue(generation),
    generationJobsProvider.overrideWithValue(jobs),
    songLibraryProvider.overrideWithValue(library),
    consentSourceProvider.overrideWithValue(
      statementsFailure == null
          ? consent
          : (FakeConsentSource(failure: statementsFailure)),
    ),
    audioPlayerFactoryProvider.overrideWithValue(() => player),
    audioFilePickerProvider.overrideWithValue(audioPicker),
    jobPollIntervalProvider.overrideWithValue(const Duration(milliseconds: 50)),
    voicePollIntervalProvider.overrideWithValue(
      const Duration(milliseconds: 50),
    ),
  ];
}

Future<void> pump(WidgetTester tester, Rig rig) async {
  tester.view.physicalSize = referenceLogicalSize * referencePixelRatio;
  tester.view.devicePixelRatio = referencePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: rig.overrides,
      child: const DeenVoiceApp(),
    ),
  );
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage('assets/art/masjid_header.webp'),
      tester.element(find.byType(DeenVoiceApp)),
    );
  });
  await settle(tester);
}

/// `pumpAndSettle` never returns while a progress indicator animates, so
/// advance time explicitly.
Future<void> settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> leave(WidgetTester tester) async {
  // Dispose the tree so periodic timers end before the test does.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(loadAppFonts);

  group('sign-in gate', () {
    testWidgets('signed out: sign-in is shown, not the app', (tester) async {
      await pump(tester, Rig(signedIn: false));
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Generate Song'), findsNothing);
      await leave(tester);
    });

    testWidgets('a restored session goes straight to the library', (
      tester,
    ) async {
      await pump(tester, Rig());
      expect(find.text('My Songs'), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
      await leave(tester);
    });

    testWidgets('invalid input is explained without calling the service', (
      tester,
    ) async {
      final rig = Rig(signedIn: false);
      await pump(tester, rig);
      await tester.tap(find.text('Sign in').last);
      await settle(tester);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'amina@example.com',
      );
      await tester.tap(find.text('Sign in').last);
      await settle(tester);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(rig.auth.calls, isEmpty);
      await leave(tester);
    });

    testWidgets('signing in opens the library for that user', (tester) async {
      final rig = Rig(signedIn: false);
      await pump(tester, rig);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'amina@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'correct horse battery',
      );
      await tester.tap(find.text('Sign in').last);
      await settle(tester);
      expect(rig.auth.calls, ['signIn:amina@example.com']);
      expect(find.text('My Songs'), findsOneWidget);
      expect((await rig.store.read())?.email, 'amina@example.com');
      await leave(tester);
    });

    testWidgets('the server\'s message is shown when sign-in fails', (
      tester,
    ) async {
      final rig = Rig(
        signedIn: false,
      )..auth.failure = const ServiceFailure('Email or password is incorrect.');
      await pump(tester, rig);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'amina@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'wrong password!!',
      );
      await tester.tap(find.text('Sign in').last);
      await settle(tester);
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('creating an account requires a 10+ character password', (
      tester,
    ) async {
      final rig = Rig(signedIn: false);
      await pump(tester, rig);
      await tester.tap(find.text('Create a new account'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'new@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'short',
      );
      await tester.tap(find.text('Create account'));
      await settle(tester);
      expect(
        find.text('Use a password of at least 10 characters.'),
        findsOneWidget,
      );
      expect(rig.auth.calls, isEmpty);
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'long enough password',
      );
      await tester.tap(find.text('Create account'));
      await settle(tester);
      expect(rig.auth.calls, ['register:new@example.com']);
      await leave(tester);
    });

    testWidgets('signing out returns to sign-in and forgets the session', (
      tester,
    ) async {
      final rig = Rig();
      await pump(tester, rig);
      await tester.tap(find.byTooltip('Menu'));
      await settle(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(rig.auth.signOuts, 1);
      expect(await rig.store.read(), isNull);
      await leave(tester);
    });
  });

  group('library', () {
    testWidgets('empty library says so and offers to create a song', (
      tester,
    ) async {
      await pump(tester, Rig());
      expect(find.textContaining('No songs yet'), findsOneWidget);
      expect(find.text('Create a song'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('lists saved songs with their voice, language and length', (
      tester,
    ) async {
      await pump(
        tester,
        Rig(
          songs: [
            song(),
            song(id: 's2', title: 'Second', voiceName: null, duration: null),
          ],
        ),
      );
      expect(find.text('Ya Rabbi'), findsOneWidget);
      expect(find.textContaining('My Voice · english · 3:05'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
      'shows real in-progress and failed jobs, using the server\'s wording',
      (tester) async {
        final rig = Rig(songs: [song()]);
        rig.jobs.recentJobs = [
          job(
            JobStatus.processing,
            id: 'a',
            title: 'Being made',
            stage: 'Generating your song',
          ),
          job(
            JobStatus.failed,
            id: 'b',
            title: 'Did not work',
            failureMessage: 'The music service returned no audio. Your credits were returned.',
          ),
          job(
            JobStatus.completed,
            id: 'c',
            title: 'Old success',
            songId: 'song-1',
          ),
        ];
        await pump(tester, rig);
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Generating your song'), findsOneWidget);
        expect(find.text('Couldn’t be made'), findsOneWidget);
        expect(
          find.textContaining('Your credits were returned'),
          findsOneWidget,
        );
        expect(
          find.text('Old success'),
          findsNothing,
          reason: 'completed jobs appear as songs, not jobs',
        );
        await leave(tester);
      },
    );

    testWidgets(
      'a job that finishes while the library is open makes its song appear',
      (tester) async {
        final rig = Rig();
        rig.jobs.recentJobs = [
          job(
            JobStatus.processing,
            id: 'a',
            title: 'Fresh',
            stage: 'Generating your song',
          ),
        ];
        await pump(tester, rig);
        expect(find.text('Generating your song'), findsOneWidget);

        rig.library.songs.add(song(id: 'new', title: 'Fresh'));
        rig.jobs.recentJobs = [
          job(JobStatus.completed, id: 'a', title: 'Fresh', songId: 'new'),
        ];
        await tester.pump(const Duration(milliseconds: 120));
        await settle(tester);
        expect(find.text('Your songs'), findsOneWidget);
        expect(find.text('Fresh'), findsOneWidget);
        expect(find.text('In progress'), findsNothing);
        await leave(tester);
      },
    );

    testWidgets('New song opens Create Song and Back returns to the library', (
      tester,
    ) async {
      await pump(tester, Rig());
      await tester.tap(find.text('New song'));
      await settle(tester);
      expect(find.text('Generate Song'), findsWidgets);
      await tester.tap(find.bySemanticsLabel('Back'));
      await settle(tester);
      expect(find.text('My Songs'), findsOneWidget);
      await leave(tester);
    });
  });

  group('player', () {
    testWidgets(
      'opens a saved song: signed link requested, lyrics and maker shown, play/pause drive the player',
      (tester) async {
        final rig = Rig(songs: [song(provider: 'mureka')]);
        await pump(tester, rig);
        await tester.tap(find.text('Ya Rabbi').first);
        await settle(tester);

        expect(rig.library.audioRequests, ['song-1']);
        expect(rig.player.loaded.toString(), contains('/media/songs/song-1'));
        expect(find.textContaining('Made with Mureka'), findsOneWidget);
        expect(
          find.textContaining('Ya Rabbi, ka yi mana jagora'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Play'));
        await settle(tester);
        expect(rig.player.events, containsAllInOrder(['load', 'play']));
        expect(find.byTooltip('Pause'), findsOneWidget);
        await tester.tap(find.byTooltip('Pause'));
        await settle(tester);
        expect(rig.player.events.last, 'pause');
        await leave(tester);
        expect(rig.player.disposed, isTrue);
      },
    );

    testWidgets(
      'shows the maker truthfully even when it is not a real provider',
      (tester) async {
        await pump(tester, Rig(songs: [song(provider: 'test-double')]));
        await tester.tap(find.text('Ya Rabbi').first);
        await settle(tester);
        expect(find.textContaining('Made with test-double'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets('a link or player failure is explained and can be retried', (
      tester,
    ) async {
      final rig = Rig(songs: [song()])
        ..library.audioFailure = const ServiceFailure(
          'This link is invalid or has expired.',
        );
      await pump(tester, rig);
      await tester.tap(find.text('Ya Rabbi').first);
      await settle(tester);
      expect(find.text('This link is invalid or has expired.'), findsOneWidget);
      expect(find.byTooltip('Play'), findsNothing);

      rig.library.audioFailure = null;
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(find.byTooltip('Play'), findsOneWidget);
      await leave(tester);
    });

    testWidgets('rename and delete go through the library; delete asks first', (
      tester,
    ) async {
      final rig = Rig(songs: [song()]);
      await pump(tester, rig);
      await tester.tap(find.text('Ya Rabbi').first);
      await settle(tester);

      await tester.tap(find.byTooltip('Rename'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Renamed song');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(rig.library.songs.single.title, 'Renamed song');

      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);
      expect(find.textContaining('can’t be undone'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(rig.library.songs, hasLength(1));

      await tester.tap(find.byTooltip('Delete'));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(rig.library.songs, isEmpty);
      expect(find.text('My Songs'), findsOneWidget);
      await leave(tester);
    });

    testWidgets(
      'lyrics, maker and position are exposed to assistive technology',
      (tester) async {
        // Regression: a SelectableText here rendered the lyrics but exposed no text
        // to the accessibility tree (found by inspecting Chromium's DOM).
        final handle = tester.ensureSemantics();
        await pump(tester, Rig(songs: [song(provider: 'mureka')]));
        await tester.tap(find.text('Ya Rabbi').first);
        await settle(tester);
        expect(
          find.bySemanticsLabel(RegExp('Ya Rabbi, ka yi mana jagora')),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(RegExp('Made with Mureka')),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(RegExp(r'0:00 / 3:05')), findsOneWidget);
        await leave(tester);
        handle.dispose();
      },
    );

    testWidgets('Arabic lyrics are laid out right-to-left', (tester) async {
      await pump(tester, Rig(songs: [song(lyrics: 'يا رب اغفر لنا')]));
      await tester.tap(find.text('Ya Rabbi').first);
      await settle(tester);
      // The lyrics are a normal Text (exposed to screen readers) inside a
      // SelectionArea, laid out right-to-left because the first letter is Arabic.
      final dir = Directionality.of(
        tester.element(find.text('يا رب اغفر لنا')),
      );
      expect(dir, TextDirection.rtl);
      await leave(tester);
    });
  });

  group('generation progress (real job states)', () {
    Future<void> generate(WidgetTester tester) async {
      await tester.tap(find.text('New song'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('title-field')),
        'Ya Rabbi',
      );
      await tester.enterText(
        find.byKey(const ValueKey('lyrics-field')),
        'Ya Rabbi, ka yi mana jagora',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Generate Song'));
      await settle(tester);
      await tester.tap(find.text('Generate Song'));
      await settle(tester);
    }

    testWidgets(
      'follows queued → processing → completed using only server states, then plays',
      (tester) async {
        final rig = Rig(
          songs: [song(id: 'song-9', title: 'Ya Rabbi')],
        );
        rig.jobs.script = [
          job(JobStatus.queued, stage: 'Queued'),
          job(JobStatus.processing, stage: 'Generating your song'),
          job(JobStatus.completed, stage: 'Ready', songId: 'song-9'),
        ];
        await pump(tester, rig);
        await generate(tester);

        expect(find.text('Queued'), findsOneWidget);
        expect(find.text('Cancel song'), findsOneWidget);

        rig.jobs.step = 1; // the server moved on
        await settle(tester, 4);
        expect(find.text('Generating your song'), findsOneWidget);
        expect(
          find.text('Cancel song'),
          findsNothing,
          reason: 'the provider already has it',
        );

        rig.jobs.step = 2;
        await settle(tester, 4);
        expect(find.text('Your song is ready'), findsOneWidget);
        await tester.tap(find.text('Play'));
        await settle(tester);
        expect(rig.library.audioRequests, ['song-9']);
        expect(find.textContaining('Made with Mureka'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets(
      'a failed job shows the server\'s reason and what happened to the credits',
      (tester) async {
        final rig = Rig();
        rig.jobs.script = [
          job(
            JobStatus.failed,
            failureMessage: 'We could not confirm that the music service received your request, so it was stopped and your credits were returned.',
          ),
        ];
        await pump(tester, rig);
        await generate(tester);
        expect(find.text('We couldn’t make your song'), findsOneWidget);
        expect(
          find.textContaining('your credits were returned'),
          findsOneWidget,
        );
        expect(find.text('Play'), findsNothing);
        await leave(tester);
      },
    );

    testWidgets(
      'losing contact is reported as such — the job may still be running',
      (tester) async {
        final rig = Rig();
        rig.jobs.script = [job(JobStatus.processing)];
        rig.jobs.error = const SessionExpired();
        await pump(tester, rig);
        await generate(tester);
        expect(find.text('Lost contact with DeenVoice'), findsOneWidget);
        expect(find.textContaining('may still be in progress'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets('a queued job can be cancelled', (tester) async {
      final rig = Rig();
      rig.jobs.script = [job(JobStatus.queued, stage: 'Queued')];
      await pump(tester, rig);
      await generate(tester);
      await tester.tap(find.text('Cancel song'));
      await settle(tester);
      expect(rig.jobs.cancelled, ['job-1']);
      await leave(tester);
    });
  });

  group('voices with a backend', () {
    testWidgets(
      'the consent text is the server\'s, verbatim, and its version is what gets recorded',
      (tester) async {
        final rig = Rig(voices: const []);
        await pump(tester, rig);
        await tester.tap(find.text('New song'));
        await settle(tester);
        await tester.ensureVisible(find.text('Add New Voice'));
        await settle(tester);
        await tester.tap(find.text('Add New Voice'));
        await settle(tester);

        expect(find.text(FakeConsentSource.own), findsOneWidget);
        await tester.tap(find.text('Someone who allowed me'));
        await settle(tester);
        expect(find.text(FakeConsentSource.authorized), findsOneWidget);
        expect(find.text(FakeConsentSource.own), findsNothing);

        await tester.tap(find.byType(CheckboxListTile));
        await tester.enterText(
          find.widgetWithText(TextField, 'Whose voice is this?'),
          'Aisha Bello',
        );
        await settle(tester);
        await tester.tap(find.text('Upload a recording'));
        await settle(tester);
        final e = rig.voiceRepo.enrollments.single;
        expect(e.consent.statementVersion, 'v7');
        expect(e.consent.authorizedBy, 'Aisha Bello');
        await leave(tester);
      },
    );

    testWidgets('if the consent text cannot be loaded no voice can be added', (
      tester,
    ) async {
      final rig = Rig(
        voices: const [],
        statementsFailure: const ServiceFailure('down'),
      );
      await pump(tester, rig);
      await tester.tap(find.text('New song'));
      await settle(tester);
      await tester.ensureVisible(find.text('Add New Voice'));
      await settle(tester);
      await tester.tap(find.text('Add New Voice'));
      await settle(tester);
      await tester.tap(find.byType(CheckboxListTile));
      await settle(tester);
      expect(
        find.textContaining('consent statement couldn’t be loaded'),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Upload a recording'),
          matching: find.bySubtype<FilledButton>(),
        ),
      );
      expect(button.onPressed, isNull);
      await leave(tester);
    });

    testWidgets(
      'an enrolling voice becomes selectable when the server finishes it',
      (tester) async {
        const enrolling = VoiceProfile(
          id: 'v',
          displayName: 'Imam',
          kind: VoiceKind.own,
          status: VoiceStatus.enrolling,
          supportsSinging: false,
        );
        final rig = Rig(voices: const [enrolling]);
        await pump(tester, rig);
        await tester.tap(find.text('New song'));
        await settle(tester);
        expect(find.text('Processing…'), findsOneWidget);

        rig.voiceRepo.voices
          ..clear()
          ..add(
            const VoiceProfile(
              id: 'v',
              displayName: 'Imam',
              kind: VoiceKind.own,
              status: VoiceStatus.ready,
              supportsSinging: true,
            ),
          );
        await tester.pump(const Duration(milliseconds: 120));
        await settle(tester);
        expect(find.text('Processing…'), findsNothing);
        expect(find.text('Personal voice'), findsOneWidget);
        await leave(tester);
      },
    );

    testWidgets('deleting a voice shows what the provider did not remove', (
      tester,
    ) async {
      final rig = Rig();
      rig.voiceRepo.deleteDisclosure =
          'The music provider could not delete its copy automatically.';
      await pump(tester, rig);
      await tester.tap(find.byTooltip('Menu'));
      await settle(tester);
      await tester.tap(find.text('Manage voices'));
      await settle(tester);
      await tester.tap(find.byTooltip('Delete My Voice'));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(find.textContaining('could not delete its copy'), findsOneWidget);
      await leave(tester);
    });
  });

  group('session expiry', () {
    testWidgets('a rejected session is not silently kept: sign-in returns', (
      tester,
    ) async {
      final rig = Rig();
      await pump(tester, rig);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeenVoiceApp)),
      );
      await container.read(sessionProvider.notifier).expire();
      await settle(tester);
      expect(find.text('Welcome back'), findsOneWidget);
      await leave(tester);
    });
  });
}
