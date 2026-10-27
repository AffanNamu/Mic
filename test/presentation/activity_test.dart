// Activity: what happened to the user's songs and voices, as the server said
// it, and the bell that points here.
import 'package:deenvoice/application/activity.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/session_controller.dart';
import 'package:deenvoice/data/api/session_store.dart';
import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/auth/auth.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_helpers.dart';
import '../support/screen_rig.dart';

GenerationJob finished(
  String id,
  JobStatus status, {
  required Duration ago,
  String title = 'Rabbana',
  String? songId,
  String? failureMessage,
}) => GenerationJob(
  id: id,
  status: status,
  stage: status.name,
  title: title,
  credits: 1,
  createdAt: screenNow.subtract(ago + const Duration(minutes: 4)),
  completedAt: screenNow.subtract(ago),
  songId: songId,
  failureMessage: failureMessage,
);

void main() {
  setUpAll(loadAppFonts);

  group('the screen', () {
    testWidgets('without a backend it says what it is waiting for', (
      tester,
    ) async {
      await pumpProductionApp(tester, openCreate: false);
      await openActivity(tester);
      expect(
        find.textContaining('once this build is connected'),
        findsOneWidget,
      );
    });

    testWidgets('with nothing to report it says so', (tester) async {
      await pumpScreens(tester, signedIn: true);
      await openActivity(tester);
      expect(find.textContaining('Nothing yet'), findsOneWidget);
    });

    testWidgets('every state is worded from what the server reported', (
      tester,
    ) async {
      await pumpScreens(
        tester,
        signedIn: true,
        songs: [song(id: 'b', title: 'Rabbana')],
        jobs: [
          job(
            JobStatus.processing,
            id: 'p',
            title: 'Ya Rabbi',
            stage: 'Generating your song',
          ),
          finished(
            'c',
            JobStatus.completed,
            ago: const Duration(minutes: 50),
            songId: 'b',
          ),
          finished(
            'f',
            JobStatus.failed,
            ago: const Duration(hours: 3),
            title: 'Guide Me',
            failureMessage: 'The music service returned no audio. Your credit was returned.',
          ),
          finished(
            'x',
            JobStatus.cancelled,
            ago: const Duration(days: 2),
            title: 'Changed my mind',
          ),
        ],
      );
      await openActivity(tester);
      expect(find.text('“Ya Rabbi” is being made'), findsOneWidget);
      expect(find.text('Generating your song'), findsOneWidget);
      expect(find.text('“Rabbana” is ready'), findsOneWidget);
      expect(find.text('50 minutes ago'), findsOneWidget);
      expect(find.text('“Guide Me” couldn’t be made'), findsOneWidget);
      expect(
        find.text(
          'The music service returned no audio. Your credit was returned. · 3 hours ago',
        ),
        findsOneWidget,
      );
      expect(find.text('“Changed my mind” was cancelled'), findsOneWidget);
      expect(find.text('2 days ago'), findsOneWidget);
    });

    testWidgets('a finished song opens in the player', (tester) async {
      await pumpScreens(
        tester,
        signedIn: true,
        songs: [song(id: 'b', title: 'Rabbana')],
        jobs: [
          finished(
            'c',
            JobStatus.completed,
            ago: const Duration(minutes: 5),
            songId: 'b',
          ),
        ],
      );
      await openActivity(tester);
      await tapAndSettle(tester, find.text('“Rabbana” is ready'));
      expect(find.textContaining('Made with Mureka'), findsOneWidget);
    });

    testWidgets(
      'voices that are processing or failed are listed, with the reason',
      (tester) async {
        await pumpScreens(
          tester,
          signedIn: true,
          voices: const [
            VoiceProfile(
              id: 'e',
              displayName: 'Imam',
              kind: VoiceKind.own,
              status: VoiceStatus.enrolling,
              supportsSinging: false,
            ),
            VoiceProfile(
              id: 'f',
              displayName: 'Sister Aisha',
              kind: VoiceKind.authorized,
              status: VoiceStatus.failed,
              supportsSinging: false,
              detail: 'The recording was too quiet.',
            ),
            readyOwnVoice,
          ],
        );
        await openActivity(tester);
        expect(find.text('Imam is being processed'), findsOneWidget);
        expect(find.text('Sister Aisha couldn’t be set up'), findsOneWidget);
        expect(find.text('The recording was too quiet.'), findsOneWidget);
        expect(
          find.textContaining('My Voice is'),
          findsNothing,
          reason: 'a ready voice needs no attention',
        );
        await tapAndSettle(
          tester,
          find.text('Sister Aisha couldn’t be set up'),
        );
        expect(find.text('Manage Voices'), findsWidgets);
      },
    );

    testWidgets('a failure to load is explained and can be retried', (
      tester,
    ) async {
      final jobs = FakeGenerationJobs()
        ..recentError = const ServiceFailure('The server is down.');
      await pumpScreens(tester, signedIn: true, jobsFake: jobs);
      await openActivity(tester);
      expect(find.text('The server is down.'), findsOneWidget);
      jobs.recentError = null;
      await tapAndSettle(tester, find.text('Try again'));
      expect(find.textContaining('Nothing yet'), findsOneWidget);
    });
  });

  group('the bell', () {
    final seenAt = screenNow.subtract(const Duration(hours: 1));

    testWidgets('opening Activity clears it, and remembers when', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final activity = MemoryActivityStore();
      await activity.markSeen('u', seenAt);
      await pumpScreens(
        tester,
        signedIn: true,
        activityStore: activity,
        songs: [song(id: 'b')],
        jobs: [
          finished(
            'new',
            JobStatus.completed,
            ago: const Duration(minutes: 20),
            songId: 'b',
          ),
          finished(
            'old',
            JobStatus.failed,
            ago: const Duration(hours: 5),
            title: 'Old one',
            failureMessage: 'It failed.',
          ),
        ],
      );
      expect(find.bySemanticsLabel('Activity, 1 new'), findsOneWidget);

      await openActivity(tester);
      expect(await activity.lastSeen('u'), screenNow);
      await goBack(tester);
      expect(find.bySemanticsLabel('Activity'), findsOneWidget);
      expect(find.bySemanticsLabel('Activity, 1 new'), findsNothing);
      handle.dispose();
    });

    testWidgets('what was new stays marked while the screen is open', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final activity = MemoryActivityStore();
      await activity.markSeen('u', seenAt);
      await pumpScreens(
        tester,
        signedIn: true,
        activityStore: activity,
        songs: [song(id: 'b')],
        jobs: [
          finished(
            'new',
            JobStatus.completed,
            ago: const Duration(minutes: 20),
            songId: 'b',
          ),
          finished(
            'old',
            JobStatus.failed,
            ago: const Duration(hours: 5),
            title: 'Old one',
            failureMessage: 'It failed.',
          ),
        ],
      );
      await openActivity(tester);
      expect(
        find.bySemanticsLabel(RegExp('^New\\. “Rabbana” is ready')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('^“Old one” couldn’t be made')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('^New\\. “Old one”')), findsNothing);
      handle.dispose();
    });

    testWidgets('the mark is per account: another user sees their own', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final activity = MemoryActivityStore();
      await activity.markSeen('someone-else', screenNow); // not this user
      await pumpScreens(
        tester,
        signedIn: true,
        activityStore: activity,
        songs: [song(id: 'b')],
        jobs: [
          finished(
            'c',
            JobStatus.completed,
            ago: const Duration(minutes: 20),
            songId: 'b',
          ),
        ],
      );
      expect(find.bySemanticsLabel('Activity, 1 new'), findsOneWidget);
      handle.dispose();
    });
  });

  group('unseenActivityProvider', () {
    Future<ProviderContainer> make({
      required List<GenerationJob> jobs,
      DateTime? seen,
    }) async {
      final activity = MemoryActivityStore();
      if (seen != null) await activity.markSeen('u', seen);
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          ...localStoreOverrides(activity: activity),
          apiBaseUrlProvider.overrideWithValue('https://api.example.test'),
          clockProvider.overrideWithValue(() => screenNow),
          sessionStoreProvider.overrideWithValue(
            MemorySessionStore(
              AuthSession(
                token: 't',
                userId: 'u',
                email: 'a@example.com',
                expiresAt: DateTime.utc(2030),
              ),
            ),
          ),
          generationJobsProvider.overrideWithValue(
            FakeGenerationJobs()..recentJobs = jobs,
          ),
        ],
      );
      addTearDown(c.dispose);
      c.listen(unseenActivityProvider, (_, _) {});
      await c.read(sessionProvider.future);
      await c.read(activitySeenProvider.future);
      await c.read(recentJobsProvider.future);
      return c;
    }

    test(
      'counts only songs that finished or failed after the last visit',
      () async {
        final c = await make(
          seen: screenNow.subtract(const Duration(hours: 1)),
          jobs: [
            finished(
              'a',
              JobStatus.completed,
              ago: const Duration(minutes: 10),
              songId: 's',
            ),
            finished('b', JobStatus.failed, ago: const Duration(minutes: 30)),
            finished(
              'c',
              JobStatus.completed,
              ago: const Duration(hours: 2),
              songId: 's',
            ),
            finished('d', JobStatus.cancelled, ago: const Duration(minutes: 5)),
            job(JobStatus.processing, id: 'e'),
          ],
        );
        expect(c.read(unseenActivityProvider), 2);
      },
    );

    test('before any visit every finished or failed song counts', () async {
      final c = await make(
        jobs: [
          finished(
            'a',
            JobStatus.completed,
            ago: const Duration(days: 9),
            songId: 's',
          ),
          finished('b', JobStatus.failed, ago: const Duration(days: 1)),
          job(JobStatus.queued, id: 'q'),
        ],
      );
      expect(c.read(unseenActivityProvider), 2);
    });

    test('marking seen brings it to zero', () async {
      final c = await make(
        jobs: [
          finished(
            'a',
            JobStatus.completed,
            ago: const Duration(minutes: 10),
            songId: 's',
          ),
        ],
      );
      expect(c.read(unseenActivityProvider), 1);
      await c.read(activitySeenProvider.notifier).markSeen();
      expect(c.read(unseenActivityProvider), 0);
    });

    test('a job with no finish time falls back to when it was created', () {
      final j = job(JobStatus.failed);
      expect(finishedAt(j), j.createdAt);
    });
  });
}
