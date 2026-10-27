import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/recording_controller.dart';
import 'package:deenvoice/core/theme/deen_theme.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/recording/voice_recorder.dart';
import 'package:deenvoice/presentation/voices/record_voice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_backend.dart';
import '../support/harness.dart';

class Rig {
  final mic = FakeVoiceRecorder();
  final player = FakeAudioPlayer();
  RecordedVoice? returned;
  var popped = false;
}

Future<Rig> open(
  WidgetTester tester, {
  ({int min, int max})? seconds = (min: 5, max: 15),
}) async {
  final rig = Rig();
  tester.view.physicalSize = referenceLogicalSize * referencePixelRatio;
  tester.view.devicePixelRatio = referencePixelRatio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        voiceRecorderFactoryProvider.overrideWithValue(() => rig.mic),
        audioPlayerFactoryProvider.overrideWithValue(() => rig.player),
        capabilitiesProvider.overrideWith(
          (ref) async => GenerationCapabilities(
            engineName: 'Test Engine',
            songTypes: const {},
            languages: const {},
            voiceConditioning: true,
            advancedOptionIds: const {},
            voiceSampleSeconds: seconds,
          ),
        ),
      ],
      child: MaterialApp(
        theme: buildDeenTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  rig.returned = await RecordVoiceScreen.open(context);
                  rig.popped = true;
                },
                child: const Text('open recorder'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open recorder'));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  return rig;
}

Future<void> tick(WidgetTester tester, [int frames = 4]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'shows guidance with the engine\'s stated length and a start button',
    (tester) async {
      await open(tester);
      expect(find.text('A clean sample works best'), findsOneWidget);
      expect(
        find.textContaining('Record 5 seconds to 15 seconds.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Start recording'), findsOneWidget);
      expect(
        find.textContaining('Nothing is sent when you record'),
        findsOneWidget,
      );
    },
  );

  testWidgets('without a stated length it states the conservative window', (
    tester,
  ) async {
    await open(tester, seconds: null);
    expect(
      find.textContaining('Record 5 seconds to 30 seconds.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'recording shows the live time, level and guidance on minimum length',
    (tester) async {
      final rig = await open(tester);
      await tester.tap(find.text('Start recording'));
      await tick(tester);

      expect(rig.mic.starts, 1);
      expect(find.text('0:00'), findsOneWidget);
      expect(
        find.textContaining('Keep going until at least 0:05'),
        findsOneWidget,
      );

      rig.mic.emit(const Duration(seconds: 3), 0.8);
      await tick(tester);
      expect(find.text('0:03'), findsOneWidget);
      expect(find.textContaining('Keep going'), findsOneWidget);

      rig.mic.emit(const Duration(seconds: 6), 0.5);
      await tick(tester);
      expect(find.text('0:06'), findsOneWidget);
      expect(find.textContaining('Long enough'), findsOneWidget);
      expect(find.text('Stop recording'), findsOneWidget);
    },
  );

  // These run against the semantics tree because a real browser showed that
  // the timer, hint and Stop control had been merged into a single node, so
  // "Stop recording" could not be found or operated by assistive technology.
  testWidgets('every control is its own, correctly labelled semantics node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final rig = await open(tester);

    final guidance = tester.getSemantics(
      find.bySemanticsLabel(RegExp('^A clean sample works best\$')),
    );
    expect(guidance, isSemantics(isHeader: true));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Start recording')),
      isSemantics(label: 'Start recording', isButton: true),
    );

    await tester.tap(find.text('Start recording'));
    await tick(tester);
    rig.mic.emit(const Duration(seconds: 6), 0.5);
    await tick(tester);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Stop recording')),
      isSemantics(label: 'Stop recording', isButton: true),
    );
    expect(
      find.bySemanticsLabel('Recording. 6 of 15 seconds.'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Long enough. Stop whenever you are done.'),
      findsOneWidget,
    );

    await tester.tap(find.bySemanticsLabel('Stop recording'));
    await tick(tester, 8);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Use this recording')),
      isSemantics(isButton: true, isEnabled: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Record again')),
      isSemantics(isButton: true),
    );
    handle.dispose();
  });

  testWidgets('stopping lets you listen back, then use the recording', (
    tester,
  ) async {
    final rig = await open(tester);
    await tester.tap(find.text('Start recording'));
    await tick(tester);
    rig.mic.emit(const Duration(seconds: 8));
    await tick(tester);
    await tester.tap(find.text('Stop recording'));
    await tick(tester, 8);

    expect(find.text('Your recording'), findsOneWidget);
    expect(rig.player.events, contains('loadBytes'));
    expect(rig.player.loadedBytes, rig.mic.result.wav);

    await tester.tap(find.byTooltip('Play recording'));
    await tick(tester);
    expect(rig.player.events, contains('play'));
    expect(find.byTooltip('Pause recording'), findsOneWidget);

    await tester.tap(find.text('Use this recording'));
    await tick(tester, 8);
    expect(rig.popped, isTrue);
    expect(rig.returned, rig.mic.result);
    expect(rig.returned!.fileName, 'recording.wav');
  });

  testWidgets('a too-short recording cannot be used and says why', (
    tester,
  ) async {
    final rig = await open(tester);
    rig.mic.result = fakeRecording(duration: const Duration(seconds: 3));
    await tester.tap(find.text('Start recording'));
    await tick(tester);
    await tester.tap(find.text('Stop recording'));
    await tick(tester, 8);

    expect(
      find.textContaining('That was 3 seconds. It needs to be at least 5'),
      findsOneWidget,
    );
    final use = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Use this recording'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(use.onPressed, isNull);

    await tester.tap(find.text('Record again'));
    await tick(tester);
    expect(find.text('Start recording'), findsWidgets);
    expect(rig.mic.cancels, 1);
  });

  testWidgets('a silent recording cannot be used', (tester) async {
    final rig = await open(tester);
    rig.mic.result = fakeRecording(peak: 0.01, average: 0.005);
    await tester.tap(find.text('Start recording'));
    await tick(tester);
    await tester.tap(find.text('Stop recording'));
    await tick(tester, 8);
    expect(find.textContaining('We barely heard anything'), findsOneWidget);
    final use = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Use this recording'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(use.onPressed, isNull);
  });

  testWidgets('a refused microphone is explained and can be retried', (
    tester,
  ) async {
    final rig = await open(tester);
    rig.mic.startError = const MicrophoneUnavailable();
    await tester.tap(find.text('Start recording'));
    await tick(tester);
    expect(find.textContaining('can’t use the microphone'), findsOneWidget);

    rig.mic.startError = null;
    await tester.tap(find.text('Try again'));
    await tick(tester);
    expect(find.text('Stop recording'), findsOneWidget);
  });

  testWidgets('leaving mid-recording throws the audio away', (tester) async {
    final rig = await open(tester);
    await tester.tap(find.text('Start recording'));
    await tick(tester);
    rig.mic.emit(const Duration(seconds: 2));
    await tick(tester);

    await tester.pageBack();
    await tick(tester, 8);
    expect(rig.popped, isTrue);
    expect(rig.returned, isNull);
    expect(rig.mic.cancels, greaterThanOrEqualTo(1));
    // (Disposal of the auto-dispose controller, which releases the recorder,
    // is covered in recording_controller_test.dart.)
  });

  testWidgets(
    'a recording that cannot be played back says so but can still be used',
    (tester) async {
      final rig = await open(tester);
      rig.player.loadError = StateError('no audio output');
      await tester.tap(find.text('Start recording'));
      await tick(tester);
      await tester.tap(find.text('Stop recording'));
      await tick(tester, 8);
      expect(
        find.textContaining('couldn’t be played back here'),
        findsOneWidget,
      );
      final use = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Use this recording'),
          matching: find.bySubtype<FilledButton>(),
        ),
      );
      expect(use.onPressed, isNotNull);
    },
  );
}
