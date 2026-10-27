import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/recording_controller.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/recording/voice_recorder.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_backend.dart';

void main() {
  late FakeVoiceRecorder mic;

  ProviderContainer make({({int min, int max})? sampleSeconds}) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        voiceRecorderFactoryProvider.overrideWithValue(() => mic),
        capabilitiesProvider.overrideWith(
          (ref) async => GenerationCapabilities(
            engineName: 'Test Engine',
            songTypes: const {},
            languages: const {},
            voiceConditioning: true,
            advancedOptionIds: const {},
            voiceSampleSeconds: sampleSeconds,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => mic = FakeVoiceRecorder());

  RecordingState read(ProviderContainer c) =>
      c.read(recordingControllerProvider);

  Future<void> started(
    ProviderContainer c, {
    ({int min, int max})? seconds,
  }) async {
    await c.read(capabilitiesProvider.future);
    c.listen(recordingControllerProvider, (_, _) {});
    await c.read(recordingControllerProvider.notifier).start();
  }

  test('start → progress → stop gives a reviewable recording', () async {
    final c = make(sampleSeconds: (min: 5, max: 15));
    await started(c);
    expect(read(c), isA<RecordingInProgress>());

    mic.emit(const Duration(seconds: 3), 0.6);
    await Future<void>.delayed(Duration.zero);
    final live = read(c) as RecordingInProgress;
    expect(live.elapsed, const Duration(seconds: 3));
    expect(live.level, 0.6);
    expect(live.limits.max, const Duration(seconds: 15));

    mic.result = fakeRecording();
    await c.read(recordingControllerProvider.notifier).stop();
    final review = read(c) as RecordingReview;
    expect(review.problem, isNull);
    expect(review.voice.duration, const Duration(seconds: 8));
  });

  test('stops by itself at the engine\'s maximum length', () async {
    final c = make(sampleSeconds: (min: 5, max: 15));
    await started(c);
    mic.result = fakeRecording(duration: const Duration(seconds: 15));
    mic.emit(const Duration(seconds: 15));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(mic.stops, 1);
    expect(read(c), isA<RecordingReview>());
  });

  test(
    'a recording shorter than the minimum is flagged and cannot be used',
    () async {
      final c = make(sampleSeconds: (min: 5, max: 15));
      await started(c);
      mic.result = fakeRecording(duration: const Duration(seconds: 3));
      await c.read(recordingControllerProvider.notifier).stop();
      expect((read(c) as RecordingReview).problem, RecordingProblem.tooShort);
    },
  );

  test('a recording with no signal is flagged as silent', () async {
    final c = make(sampleSeconds: (min: 5, max: 15));
    await started(c);
    mic.result = fakeRecording(peak: 0.01, average: 0.005);
    await c.read(recordingControllerProvider.notifier).stop();
    expect((read(c) as RecordingReview).problem, RecordingProblem.silent);
  });

  test('without a stated length the conservative fallback applies', () async {
    final c = make();
    await started(c);
    expect((read(c) as RecordingInProgress).limits, RecordingLimits.fallback);
  });

  test(
    'a refused microphone is an error with a message, and can be retried',
    () async {
      final c = make();
      mic.startError = const MicrophoneUnavailable();
      await started(c);
      expect((read(c) as RecordingError).message, contains('microphone'));

      mic.startError = null;
      await c.read(recordingControllerProvider.notifier).start();
      expect(read(c), isA<RecordingInProgress>());
    },
  );

  test('an unexpected capture failure never leaks internals', () async {
    final c = make();
    mic.startError = StateError('device 0x13 exploded');
    await started(c);
    final msg = (read(c) as RecordingError).message;
    expect(msg, isNot(contains('0x13')));
    expect(msg, contains('couldn’t be completed'));
  });

  test('a second start while recording is ignored', () async {
    final c = make();
    await started(c);
    await c.read(recordingControllerProvider.notifier).start();
    expect(mic.starts, 1);
  });

  test('discard throws the audio away and returns to the start', () async {
    final c = make();
    await started(c);
    await c.read(recordingControllerProvider.notifier).discard();
    expect(read(c), isA<RecordingIdle>());
    expect(mic.cancels, 1);
  });

  test(
    'leaving the screen (disposing the controller) releases the microphone',
    () async {
      final c = make();
      await started(c);
      c.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(mic.disposed, isTrue);
    },
  );
}
