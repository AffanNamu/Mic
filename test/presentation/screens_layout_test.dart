// The new screens must lay out without overflow on small phones, large text,
// tablets and landscape, in their fullest state (the one with the most content).
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_helpers.dart';
import '../support/screen_rig.dart';

const sizes = <String, Size>{
  'reference (426x923)': Size(426, 923),
  'iPhone 15 (393x852)': Size(393, 852),
  'iPhone SE (320x568)': Size(320, 568),
  'small Android (360x640)': Size(360, 640),
  'tablet portrait (768x1024)': Size(768, 1024),
  'landscape phone (844x390)': Size(844, 390),
};

final _songs = [
  song(id: 'a', title: 'A fairly long song title that keeps going and going'),
  song(
    id: 'b',
    title: 'Rabbana',
    duration: const Duration(minutes: 4, seconds: 18),
  ),
  song(id: 'c', title: 'Guide Me'),
];

final _jobs = [
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
    failureMessage: 'We could not confirm that the music service received your request, so it was stopped and your credits were returned.',
  ),
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
];

DraftStore _draft() => MemoryDraftStore(
  SavedDraft(
    draft: const SongDraft(
      title: 'A draft with a rather long title to test wrapping',
      lyrics: 'words',
    ),
    savedAt: screenNow.subtract(const Duration(hours: 2)),
    ownerId: 'u',
  ),
);

Future<void> full(WidgetTester tester, Size size) => pumpScreens(
  tester,
  signedIn: true,
  size: size,
  songs: _songs,
  jobs: _jobs,
  drafts: _draft(),
  voices: const [readyOwnVoice, readyAuthorizedVoice],
);

void main() {
  setUpAll(loadAppFonts);

  for (final scale in [1.0, 1.3]) {
    group('text scale $scale', () {
      for (final entry in sizes.entries) {
        final label = entry.key;
        final size = entry.value;

        void check(String screen, Future<void> Function(WidgetTester) run) {
          testWidgets('$screen on $label', (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            await run(tester);
            expect(tester.takeException(), isNull);
          });
        }

        check('onboarding', (tester) async {
          await pumpScreens(
            tester,
            signedIn: false,
            onboarded: false,
            size: size,
          );
          await tapAndSettle(tester, find.text('Next'));
          await tapAndSettle(tester, find.text('Next'));
        });
        check(
          'welcome',
          (tester) => pumpScreens(tester, signedIn: false, size: size),
        );
        check('welcome email form', (tester) async {
          await pumpScreens(tester, signedIn: false, size: size);
          await tester.ensureVisible(find.text('Continue with Email'));
          await tapAndSettle(tester, find.text('Continue with Email'));
          await tester.ensureVisible(find.text('Create a new account'));
          await tapAndSettle(tester, find.text('Create a new account'));
        });
        check('home with everything', (tester) => full(tester, size));
        check(
          'home with nothing',
          (tester) => pumpScreens(tester, signedIn: true, size: size),
        );
        check('home not connected', (tester) async {
          tester.view.physicalSize = size * referencePixelRatio;
          tester.view.devicePixelRatio = referencePixelRatio;
          addTearDown(tester.view.reset);
          await pumpProductionApp(tester, openCreate: false, size: size);
        });
        check('library', (tester) async {
          await full(tester, size);
          await openTab(tester, 'Library');
        });
        check('my voice', (tester) async {
          await full(tester, size);
          await openTab(tester, 'My Voice');
        });
        check('activity', (tester) async {
          await full(tester, size);
          await openActivity(tester);
        });
        check('profile', (tester) async {
          await full(tester, size);
          await openProfile(tester);
        });
      }
    });
  }
}
