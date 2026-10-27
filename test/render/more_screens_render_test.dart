@Tags(['render'])
library;

import 'package:deenvoice/domain/library/library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_rig.dart';

/// Renders the other new screens for review, and fails on any layout overflow.
/// Output: build/renders/screens/.
Future<void> _settle(WidgetTester tester, [int frames = 14]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _shot(WidgetTester tester, String name) =>
    savePng(tester, 'build/renders/screens/$name.png');

final _jobs = [
  GenerationJob(
    id: 'p',
    status: JobStatus.processing,
    stage: 'Generating your song',
    title: 'Ya Rabbi',
    credits: 1,
    createdAt: screenNow.subtract(const Duration(minutes: 2)),
  ),
  GenerationJob(
    id: 'f',
    status: JobStatus.failed,
    stage: 'Failed',
    title: 'Guide Me',
    credits: 1,
    createdAt: screenNow.subtract(const Duration(hours: 3)),
    completedAt: screenNow.subtract(const Duration(hours: 3)),
    failureMessage:
        'The music service returned no audio. Your credit was returned.',
  ),
  GenerationJob(
    id: 'c',
    status: JobStatus.completed,
    stage: 'Ready',
    title: 'Rabbana',
    credits: 1,
    createdAt: screenNow.subtract(const Duration(hours: 1)),
    completedAt: screenNow.subtract(const Duration(minutes: 50)),
    songId: 'b',
  ),
];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('onboarding pages', (tester) async {
    await pumpScreens(tester, signedIn: false, onboarded: false);
    await _shot(tester, 'onboarding_1');
    await tester.tap(find.text('Next'));
    await _settle(tester);
    await _shot(tester, 'onboarding_2');
    await tester.tap(find.text('Next'));
    await _settle(tester);
    await _shot(tester, 'onboarding_3');
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('welcome email form and the language sheet', (tester) async {
    await pumpScreens(tester, signedIn: false);
    await tester.tap(find.text('Continue with Email'));
    await _settle(tester);
    await _shot(tester, 'welcome_email');
    await tester.tap(find.text('Other ways to continue'));
    await _settle(tester);
    await tester.tap(find.text('English'));
    await _settle(tester);
    await _shot(tester, 'language_sheet');
  });

  testWidgets('tabs, activity and profile', (tester) async {
    await pumpScreens(
      tester,
      signedIn: true,
      songs: [
        song(
          id: 'a',
          title: 'Ya Rabbi',
          duration: const Duration(minutes: 3, seconds: 42),
        ),
        song(
          id: 'b',
          title: 'Rabbana',
          duration: const Duration(minutes: 4, seconds: 18),
        ),
      ],
      jobs: _jobs,
      voices: const [readyOwnVoice, readyAuthorizedVoice],
    );
    await tester.tap(find.text('How it works'));
    await _settle(tester);
    await _shot(tester, 'how_it_works');
    await tester.tapAt(const Offset(10, 100)); // dismiss the sheet
    await _settle(tester);

    await tester.tap(find.text('Library').last);
    await _settle(tester);
    await _shot(tester, 'library');

    await tester.tap(find.text('My Voice').last);
    await _settle(tester);
    await _shot(tester, 'my_voice');

    await tester.tap(find.text('Home'));
    await _settle(tester);
    await tester.tap(
      find.byTooltip('Draft options').evaluate().isEmpty
          ? find.text('A')
          : find.text('A'),
    );
    await _settle(tester);
    await _shot(tester, 'profile');
  });

  testWidgets('activity', (tester) async {
    await pumpScreens(tester, signedIn: true, jobs: _jobs);
    // The bell is the round button left of the avatar.
    await tester.tapAt(const Offset(346, 68));
    await _settle(tester);
    await _shot(tester, 'activity');
    expect(find.text('Activity'), findsOneWidget);
  });
}
