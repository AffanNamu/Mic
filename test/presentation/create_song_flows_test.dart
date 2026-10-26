import 'dart:async';
import 'dart:typed_data';

import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/generation/generation_request.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  setUpAll(loadAppFonts);

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(DeenVoiceApp)));
  SongDraft draft(WidgetTester tester) =>
      container(tester).read(songDraftProvider).draft;

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  final lyricsField = find.byKey(const ValueKey('lyrics-field'));
  final titleField = find.byKey(const ValueKey('title-field'));

  TestEnv env({
    List<VoiceProfile> voices = const [
      readyOwnVoice,
      readyAuthorizedVoice,
      readySystemVoice,
    ],
    int credits = 120,
    FakeGenerationService? generation,
    LyricsAssistant? lyrics,
    TextFilePicker? textPicker,
    AudioFilePicker? audioPicker,
    FakeVoiceRepository? voiceRepo,
  }) => TestEnv(
    voices: voiceRepo ?? FakeVoiceRepository(voices),
    credits: FakeCreditsRepository(credits),
    generation: generation,
    lyrics: lyrics,
    textPicker: textPicker,
    audioPicker: audioPicker,
  );

  group('song type', () {
    testWidgets('selecting a card updates the draft and the selection', (
      tester,
    ) async {
      await pumpApp(tester, env());
      expect(draft(tester).type, SongType.fullSong);

      for (final type in SongType.values) {
        await tapVisible(tester, find.text(type.label));
        expect(draft(tester).type, type);
      }
    });

    testWidgets('Instrumental dims voice selection and drops requirements', (
      tester,
    ) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('Instrumental'));

      expect(
        find.text('Instrumental songs don’t use a voice.'),
        findsOneWidget,
      );

      // Title alone is now enough to generate.
      await tester.enterText(titleField, 'Ambient');
      await tapVisible(tester, find.text('Generate Song'));
      expect(find.text('Your song is in the queue'), findsOneWidget);
    });

    testWidgets('a type the connected engine cannot do is disabled', (
      tester,
    ) async {
      await pumpApp(
        tester,
        env(
          generation: FakeGenerationService(
            capabilities: const GenerationCapabilities(
              engineName: 'Eng',
              songTypes: {SongType.fullSong},
              languages: {...SongLanguage.values},
              voiceConditioning: true,
              advancedOptionIds: {},
            ),
          ),
        ),
      );

      expect(find.text('Not supported by Eng'), findsNWidgets(3));
      await tester.tap(find.text('Instrumental'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(draft(tester).type, SongType.fullSong);
    });

    testWidgets('Nasheed Style applies its template defaults', (tester) async {
      await pumpApp(tester, env());
      container(tester).read(songDraftProvider.notifier)
        ..setGenre(SongGenre.qasida)
        ..setMood(SongMood.joyful);
      await tester.pump();

      await tapVisible(tester, find.text('Nasheed Style'));

      expect(draft(tester).genre, SongGenre.islamicNasheed);
      expect(draft(tester).mood, SongMood.peaceful);
    });
  });

  group('voice selection', () {
    testWidgets('shows the user’s real voices and selects by tap', (
      tester,
    ) async {
      await pumpApp(tester, env());

      expect(find.text('My Voice'), findsOneWidget);
      expect(find.text('Sister Aisha'), findsOneWidget);
      expect(find.text('Studio Voice'), findsOneWidget);
      // The personal voice is the default.
      expect(container(tester).read(selectedVoiceIdProvider), 'voice-own');

      await tapVisible(tester, find.text('Sister Aisha'));
      expect(draft(tester).voiceId, 'voice-aisha');
      expect(container(tester).read(selectedVoiceIdProvider), 'voice-aisha');
    });

    testWidgets('a voice that is not ready explains why instead of selecting', (
      tester,
    ) async {
      const enrolling = VoiceProfile(
        id: 'voice-new',
        displayName: 'New Voice',
        kind: VoiceKind.own,
        status: VoiceStatus.enrolling,
        supportsSinging: true,
      );
      await pumpApp(tester, env(voices: [readyOwnVoice, enrolling]));

      await tapVisible(tester, find.text('New Voice'));

      expect(find.text('New Voice is still being prepared.'), findsOneWidget);
      expect(draft(tester).voiceId, isNull);
    });

    testWidgets('a speech-only voice cannot be chosen for singing', (
      tester,
    ) async {
      const speech = VoiceProfile(
        id: 'voice-speech',
        displayName: 'Speech Clone',
        kind: VoiceKind.own,
        status: VoiceStatus.ready,
        supportsSinging: false,
      );
      await pumpApp(tester, env(voices: [speech]));

      await tapVisible(tester, find.text('Speech Clone'));

      expect(
        find.textContaining('can’t be used for singing, only speech'),
        findsOneWidget,
      );
      expect(container(tester).read(selectedVoiceIdProvider), isNull);
    });

    testWidgets('with several voices the row scrolls instead of overflowing', (
      tester,
    ) async {
      final many = [
        readyOwnVoice,
        for (var i = 0; i < 6; i++)
          VoiceProfile(
            id: 'extra-$i',
            displayName: 'Voice $i',
            kind: VoiceKind.authorized,
            status: VoiceStatus.ready,
            supportsSinging: true,
          ),
      ];
      await pumpApp(tester, env(voices: many));
      expect(tester.takeException(), isNull);
      expect(find.text('Voice 0'), findsOneWidget);
    });
  });

  group('voice management', () {
    testWidgets('lists voices and deletes one after confirmation', (
      tester,
    ) async {
      final repo = FakeVoiceRepository(const [
        readyOwnVoice,
        readyAuthorizedVoice,
      ]);
      await pumpApp(tester, env(voiceRepo: repo));

      await tapVisible(tester, find.text('Manage Voices'));
      expect(find.text('Your voice · Personal voice'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete Sister Aisha'));
      await tester.pumpAndSettle();
      expect(find.text('Delete Sister Aisha?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(repo.voices.map((v) => v.id), ['voice-own']);
      expect(find.text('Sister Aisha was deleted.'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation deletes nothing', (tester) async {
      final repo = FakeVoiceRepository(const [readyOwnVoice]);
      await pumpApp(tester, env(voiceRepo: repo));

      await tapVisible(tester, find.text('Manage Voices'));
      await tester.tap(find.byTooltip('Delete My Voice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repo.voices, hasLength(1));
    });

    testWidgets('system voices cannot be deleted by the user', (tester) async {
      await pumpApp(tester, env(voices: const [readySystemVoice]));
      await tapVisible(tester, find.text('Manage Voices'));
      expect(find.byTooltip('Delete Studio Voice'), findsNothing);
    });
  });

  group('add voice (upload entry)', () {
    final audio = PickedAudio(
      fileName: 'me.wav',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
    );

    testWidgets('upload stays disabled until consent is given', (tester) async {
      await pumpApp(tester, env(audioPicker: FakeAudioFilePicker(audio)));
      await tapVisible(tester, find.text('Add New Voice'));

      FilledButton upload() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Upload a recording'),
      );
      expect(upload().onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(upload().onPressed, isNotNull);
    });

    testWidgets('a blank name keeps upload disabled', (tester) async {
      await pumpApp(tester, env(audioPicker: FakeAudioFilePicker(audio)));
      await tapVisible(tester, find.text('Add New Voice'));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.enterText(find.widgetWithText(TextField, 'My Voice'), '  ');
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Upload a recording'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('records who the voice belongs to with the consent', (
      tester,
    ) async {
      final repo = FakeVoiceRepository(const []);
      await pumpApp(
        tester,
        env(voiceRepo: repo, audioPicker: FakeAudioFilePicker(audio)),
      );
      await tapVisible(tester, find.text('Add New Voice'));

      await tester.tap(find.text('Someone who allowed me'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The speaker has given me explicit permission'),
        findsOneWidget,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.enterText(
        find.widgetWithText(TextField, 'My Voice'),
        'Aisha',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload a recording'));
      await tester.pumpAndSettle();

      expect(repo.enrollments, hasLength(1));
      final e = repo.enrollments.single;
      expect(e.displayName, 'Aisha');
      expect(e.fileName, 'me.wav');
      expect(e.audio, [1, 2, 3, 4]);
      expect(e.consent.ownership, VoiceOwnership.authorizedByOwner);
      expect(e.consent.acceptedAt.isUtc, isTrue);
      expect(find.textContaining('Voice submitted'), findsOneWidget);
      // The new profile appears, still processing.
      expect(find.text('Aisha'), findsOneWidget);
      expect(find.text('Processing…'), findsOneWidget);
    });

    testWidgets('cancelling the file picker enrolls nothing', (tester) async {
      final repo = FakeVoiceRepository(const []);
      await pumpApp(
        tester,
        env(voiceRepo: repo, audioPicker: FakeAudioFilePicker(null)),
      );
      await tapVisible(tester, find.text('Add New Voice'));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload a recording'));
      await tester.pumpAndSettle();

      expect(repo.enrollments, isEmpty);
    });

    testWidgets('a rejected file shows the reason', (tester) async {
      await pumpApp(
        tester,
        env(
          audioPicker: FakeAudioFilePicker(
            null,
            error: const ServiceFailure('That recording is larger than 25 MB.'),
          ),
        ),
      );
      await tapVisible(tester, find.text('Add New Voice'));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload a recording'));
      await tester.pumpAndSettle();

      expect(find.text('That recording is larger than 25 MB.'), findsOneWidget);
    });

    testWidgets('in-app recording is offered as unavailable, not faked', (
      tester,
    ) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('Add New Voice'));

      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Record now'),
            )
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Recording inside the app isn’t available'),
        findsOneWidget,
      );
    });
  });

  group('lyrics', () {
    testWidgets('typing updates the draft and the counter', (tester) async {
      await pumpApp(tester, env());
      await tester.enterText(lyricsField, 'Ya Rabbi');
      await tester.pump();

      expect(draft(tester).lyrics, 'Ya Rabbi');
      expect(find.text('8/3000'), findsOneWidget);
    });

    testWidgets('input is capped at 3000 characters', (tester) async {
      await pumpApp(tester, env());
      await tester.enterText(lyricsField, 'a' * 3500);
      await tester.pump();

      expect(draft(tester).lyrics.length, 3000);
      expect(find.text('3000/3000'), findsOneWidget);
    });

    testWidgets('Arabic lyrics switch the editor to right-to-left', (
      tester,
    ) async {
      await pumpApp(tester, env());
      await tester.enterText(lyricsField, 'يا رب');
      await tester.pump();

      expect(
        tester.widget<TextField>(lyricsField).textDirection,
        TextDirection.rtl,
      );

      await tester.enterText(lyricsField, 'Ya Rabbi');
      await tester.pump();
      expect(
        tester.widget<TextField>(lyricsField).textDirection,
        TextDirection.ltr,
      );
    });

    testWidgets('lyrics keep Arabic, Hausa and English text intact', (
      tester,
    ) async {
      await pumpApp(tester, env());
      const mixed = 'يا رب\nYa Allah, ka ji mu\nPraise be';
      await tester.enterText(lyricsField, mixed);
      await tester.pump();
      expect(draft(tester).lyrics, mixed);
    });
  });

  group('text import', () {
    testWidgets('imports a file into empty lyrics', (tester) async {
      await pumpApp(
        tester,
        env(
          textPicker: FakeTextFilePicker(
            const PickedText(fileName: 'nasheed.txt', text: '  Ya Rabbi  \n'),
          ),
        ),
      );

      await tapVisible(tester, find.text('Import Text'));

      expect(draft(tester).lyrics, 'Ya Rabbi');
      expect(
        tester.widget<TextField>(lyricsField).controller!.text,
        'Ya Rabbi',
        reason: 'the editor shows the imported text',
      );
    });

    testWidgets('asks before replacing existing lyrics', (tester) async {
      await pumpApp(
        tester,
        env(
          textPicker: FakeTextFilePicker(
            const PickedText(fileName: 'new.txt', text: 'New words'),
          ),
        ),
      );
      await tester.enterText(lyricsField, 'My words');

      await tapVisible(tester, find.text('Import Text'));
      expect(find.text('Replace your lyrics?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(draft(tester).lyrics, 'My words');

      await tapVisible(tester, find.text('Import Text'));
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(draft(tester).lyrics, 'New words');
    });

    testWidgets('over-long text is cut and the user is told', (tester) async {
      await pumpApp(
        tester,
        env(
          textPicker: FakeTextFilePicker(
            PickedText(fileName: 'long.txt', text: 'a' * 4000),
          ),
        ),
      );

      await tapVisible(tester, find.text('Import Text'));

      expect(draft(tester).lyrics.length, 3000);
      expect(find.textContaining('cut to 3000 characters'), findsOneWidget);
    });

    testWidgets('an empty file is reported and changes nothing', (
      tester,
    ) async {
      await pumpApp(
        tester,
        env(
          textPicker: FakeTextFilePicker(
            const PickedText(fileName: 'e.txt', text: ' \n '),
          ),
        ),
      );
      await tester.enterText(lyricsField, 'keep');

      await tapVisible(tester, find.text('Import Text'));

      expect(find.text('“e.txt” is empty.'), findsOneWidget);
      expect(draft(tester).lyrics, 'keep');
    });

    testWidgets('a rejected file shows the reason; cancel does nothing', (
      tester,
    ) async {
      await pumpApp(
        tester,
        env(
          textPicker: FakeTextFilePicker(
            null,
            error: const ServiceFailure('That file isn’t UTF-8 text.'),
          ),
        ),
      );
      await tapVisible(tester, find.text('Import Text'));
      expect(find.text('That file isn’t UTF-8 text.'), findsOneWidget);

      await pumpApp(tester, env(textPicker: FakeTextFilePicker(null)));
      await tapVisible(tester, find.text('Import Text'));
      expect(draft(tester).lyrics, isEmpty);
    });
  });

  group('AI lyrics actions (with a working assistant)', () {
    testWidgets('Write with AI shows a reviewable suggestion and applies it', (
      tester,
    ) async {
      await pumpApp(
        tester,
        env(
          lyrics: FakeLyricsAssistant(
            writeResult: const LyricsSuggestion(
              'Ya Rabbi, ka yi mana jagora',
              notes: ['Please check the Hausa pronunciation.'],
            ),
          ),
        ),
      );

      await tapVisible(tester, find.text('Write with AI'));
      expect(
        find.textContaining(
          'Writing Hausa lyrics · Islamic Nasheed · Peaceful',
        ),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'What is the song about?'),
        'guidance',
      );
      await tester.tap(find.text('Write lyrics'));
      await tester.pumpAndSettle();

      expect(find.text('Ya Rabbi, ka yi mana jagora'), findsOneWidget);
      expect(
        find.textContaining('check the Hausa pronunciation'),
        findsOneWidget,
      );
      expect(draft(tester).lyrics, isEmpty, reason: 'nothing applied yet');

      await tester.tap(find.text('Use these lyrics'));
      await tester.pumpAndSettle();
      expect(draft(tester).lyrics, 'Ya Rabbi, ka yi mana jagora');
    });

    testWidgets('Write with AI needs a topic', (tester) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('Write with AI'));
      await tester.tap(find.text('Write lyrics'));
      await tester.pumpAndSettle();
      expect(
        find.text('Tell the assistant what the song is about.'),
        findsOneWidget,
      );
    });

    testWidgets('AI Improve on empty lyrics explains what to do', (
      tester,
    ) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('AI Improve'));
      expect(find.textContaining('Add some lyrics first'), findsOneWidget);
    });

    testWidgets('AI Improve is reviewed before anything changes', (
      tester,
    ) async {
      await pumpApp(
        tester,
        env(
          lyrics: FakeLyricsAssistant(
            improveResult: const LyricsSuggestion('Ya Rabbi (polished)'),
          ),
        ),
      );
      await tester.enterText(lyricsField, 'Ya Rabbi');

      await tapVisible(tester, find.text('AI Improve'));
      expect(find.text('Review suggestion'), findsOneWidget);
      expect(find.text('Ya Rabbi (polished)'), findsOneWidget);
      await tester.tap(find.text('Keep mine'));
      await tester.pumpAndSettle();
      expect(draft(tester).lyrics, 'Ya Rabbi');

      await tapVisible(tester, find.text('AI Improve'));
      await tester.tap(find.text('Use suggestion'));
      await tester.pumpAndSettle();
      expect(draft(tester).lyrics, 'Ya Rabbi (polished)');
    });
  });

  group('song details', () {
    testWidgets('title is stored', (tester) async {
      await pumpApp(tester, env());
      await tester.enterText(titleField, 'Ya Rabbi');
      expect(draft(tester).title, 'Ya Rabbi');
    });

    testWidgets('language picker offers Hausa, Arabic and English', (
      tester,
    ) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('Hausa'));

      for (final language in ['Hausa', 'Arabic', 'English', 'Mixed']) {
        expect(find.text(language), findsWidgets, reason: language);
      }
      await tester.tap(find.text('Arabic'));
      await tester.pumpAndSettle();
      expect(draft(tester).language, SongLanguage.arabic);
      expect(find.text('Arabic'), findsOneWidget, reason: 'shown on the field');
    });

    testWidgets('every setting picker writes its choice to the draft', (
      tester,
    ) async {
      await pumpApp(tester, env());
      final cases =
          <(String current, String choose, bool Function(SongDraft) ok)>[
            ('Islamic Nasheed', 'Qasida', (d) => d.genre == SongGenre.qasida),
            ('Peaceful', 'Joyful', (d) => d.mood == SongMood.joyful),
            ('Normal', 'Upbeat', (d) => d.tempo == SongTempo.upbeat),
            (
              '3 - 4 minutes',
              '1 - 2 minutes',
              (d) => d.duration == SongDuration.oneToTwo,
            ),
            (
              'Balanced',
              'Powerful',
              (d) => d.intensity == VocalIntensity.powerful,
            ),
            (
              'Traditional',
              'Vocals only',
              (d) => d.instruments == InstrumentSet.vocalsOnly,
            ),
          ];
      for (final (current, choose, ok) in cases) {
        await tapVisible(tester, find.text(current));
        await tester.tap(find.text(choose).last);
        await tester.pumpAndSettle();
        expect(ok(draft(tester)), isTrue, reason: '$current → $choose');
      }
    });

    testWidgets('over-long titles are capped', (tester) async {
      await pumpApp(tester, env());
      await tester.enterText(titleField, 'x' * 200);
      expect(draft(tester).title.length, SongDraft.maxTitleLength);
    });
  });

  group('advanced options (with an engine)', () {
    testWidgets('supported options change the draft; others are inert', (
      tester,
    ) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('Advanced Options'));

      expect(
        find.textContaining('Settings supported by Test Engine'),
        findsOneWidget,
      );
      expect(find.text('Not supported by Test Engine'), findsNWidgets(2));

      await tester.tap(find.text('Low'));
      await tester.pumpAndSettle();
      expect(draft(tester).advanced['pitch_range'], 'low');

      await tester.tap(find.text('Layered'));
      await tester.pumpAndSettle();
      expect(draft(tester).advanced.containsKey('arrangement'), isFalse);
    });

    testWidgets('expands and collapses', (tester) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('Advanced Options'));
      expect(find.text('Pitch range'), findsOneWidget);
      await tester.tap(find.text('Advanced Options'));
      await tester.pumpAndSettle();
      expect(find.text('Pitch range'), findsNothing);
    });
  });

  group('generate', () {
    Future<void> fillForm(WidgetTester tester) async {
      await tester.enterText(titleField, 'Ya Rabbi');
      await tester.enterText(lyricsField, 'Ya Rabbi, ka yi mana jagora');
      await tester.pump();
    }

    testWidgets('a valid request is accepted and reported with its receipt', (
      tester,
    ) async {
      final generation = FakeGenerationService();
      await pumpApp(tester, env(generation: generation));
      await fillForm(tester);

      await tapVisible(tester, find.text('Generate Song'));

      expect(find.text('Your song is in the queue'), findsOneWidget);
      expect(find.textContaining('Job job-1 is queued'), findsOneWidget);
      expect(generation.submitted, hasLength(1));
      final request = generation.submitted.single;
      expect(request.voiceId, 'voice-own');
      expect(request.draft.language, SongLanguage.hausa);
      expect(request.draft.lyrics, 'Ya Rabbi, ka yi mana jagora');
    });

    testWidgets('the button shows progress and ignores taps while submitting', (
      tester,
    ) async {
      final generation = FakeGenerationService()
        ..gate = Completer<GenerationReceipt>();
      await pumpApp(tester, env(generation: generation));
      await fillForm(tester);

      await tester.ensureVisible(find.text('Generate Song'));
      await tester.tap(find.text('Generate Song'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Starting…'), findsOneWidget);

      await tester.tap(find.text('Starting…'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(generation.submitted, hasLength(1));

      generation.gate!.complete(
        const GenerationReceipt(
          jobId: 'j-9',
          status: GenerationStatus.processing,
          creditsReserved: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Job j-9 is processing'), findsOneWidget);
      expect(find.text('Generate Song'), findsOneWidget);
    });

    testWidgets('invalid input scrolls to and shows each problem', (
      tester,
    ) async {
      await pumpApp(tester, env());
      await tapVisible(tester, find.text('Generate Song'));

      expect(find.text('Give your song a title.'), findsWidgets);
      expect(find.text('Add lyrics, or use Write with AI.'), findsWidgets);

      // Let the snackbar expire so only inline errors remain.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Give your song a title.'), findsOneWidget);

      await tester.enterText(titleField, 'T');
      await tester.pump();
      expect(find.text('Give your song a title.'), findsNothing);
      expect(find.text('Add lyrics, or use Write with AI.'), findsOneWidget);
    });

    testWidgets('too few credits opens the credits sheet', (tester) async {
      final generation = FakeGenerationService();
      await pumpApp(tester, env(credits: 0, generation: generation));
      await fillForm(tester);

      await tapVisible(tester, find.text('Generate Song'));

      expect(find.text('You need 1 credit but have 0.'), findsOneWidget);
      expect(find.text('0 credits available'), findsWidgets);
      expect(generation.submitted, isEmpty);
    });

    testWidgets('an engine failure is shown and nothing is accepted', (
      tester,
    ) async {
      final generation = FakeGenerationService(
        failure: const ServiceFailure('The provider is busy. Try again soon.'),
      );
      await pumpApp(tester, env(generation: generation));
      await fillForm(tester);

      await tapVisible(tester, find.text('Generate Song'));

      expect(
        find.text('The provider is busy. Try again soon.'),
        findsOneWidget,
      );
      expect(find.text('Your song is in the queue'), findsNothing);
    });

    testWidgets('the button label tracks the estimated cost', (tester) async {
      await pumpApp(tester, env());
      expect(find.text('1 Credit'), findsOneWidget);
    });
  });

  group('credits', () {
    testWidgets('the pill shows the real balance and opens the credits sheet', (
      tester,
    ) async {
      await pumpApp(tester, env(credits: 42));
      expect(find.text('42 Credits'), findsOneWidget);

      await tester.tap(find.text('42 Credits'));
      await tester.pumpAndSettle();
      expect(find.text('42 credits available'), findsOneWidget);
      expect(
        find.textContaining('Buying more credits isn’t available'),
        findsOneWidget,
      );
    });

    testWidgets('the plus button opens the same entry point', (tester) async {
      await pumpApp(tester, env(credits: 7));
      await tester.tap(find.byIcon(LucideIcons.plus).first);
      await tester.pumpAndSettle();
      expect(find.text('7 credits available'), findsOneWidget);
    });

    testWidgets('refresh re-reads the balance', (tester) async {
      final credits = FakeCreditsRepository(5);
      await pumpApp(
        tester,
        TestEnv(voices: FakeVoiceRepository(const []), credits: credits),
      );
      await tester.tap(find.text('5 Credits'));
      await tester.pumpAndSettle();

      credits.credits = 9;
      await tester.tap(find.text('Refresh balance'));
      await tester.pumpAndSettle();

      expect(find.text('9 credits available'), findsOneWidget);
    });
  });
}
