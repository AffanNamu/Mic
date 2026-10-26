import 'dart:async';

import 'package:deenvoice/application/generation_controller.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/data/unconfigured_services.dart';
import 'package:deenvoice/domain/failures.dart';
import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/generation/generation_request.dart';
import 'package:deenvoice/domain/services.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:deenvoice/domain/song/song_validation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// Counts calls so tests can prove what was (not) asked of the backend.
class _SpyCredits implements CreditsRepository {
  _SpyCredits(this.credits, {this.error});

  int credits;
  Object? error;
  int calls = 0;

  @override
  Future<int> balance() async {
    calls++;
    if (error != null) throw error!;
    return credits;
  }
}

ProviderContainer _container({
  FakeGenerationService? generation,
  CreditsRepository? credits,
  bool withVoice = true,
}) {
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      voiceRepositoryProvider.overrideWithValue(
        FakeVoiceRepository(withVoice ? [readyOwnVoice] : const []),
      ),
      creditsRepositoryProvider.overrideWithValue(
        credits ?? FakeCreditsRepository(120),
      ),
      songGenerationServiceProvider.overrideWithValue(
        generation ?? FakeGenerationService(),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void _fillValidDraft(ProviderContainer c) {
  c.read(songDraftProvider.notifier)
    ..setTitle('Ya Rabbi')
    ..setLyrics('Ya Rabbi, ka yi mana jagora');
}

GenerationController _controller(ProviderContainer c) =>
    c.read(generationControllerProvider.notifier);

GenerationProblem _problem(ProviderContainer c) {
  final state = c.read(generationControllerProvider);
  expect(state, isA<GenerationRejected>());
  return (state as GenerationRejected).problem;
}

void main() {
  group('with no backend configured (the shipped defaults)', () {
    test('an otherwise valid song is refused as engine-unavailable', () async {
      final c = ProviderContainer(retry: (_, _) => null);
      addTearDown(c.dispose);
      // Instrumental needs no lyrics or voice, so only the engine is missing.
      c.read(songDraftProvider.notifier)
        ..setType(SongType.instrumental)
        ..setTitle('Ambient');

      await _controller(c).submit();

      expect(_problem(c), isA<EngineUnavailable>());
    });

    test('a vocal song is refused for the missing voice first', () async {
      final c = ProviderContainer(retry: (_, _) => null);
      addTearDown(c.dispose);
      c.read(songDraftProvider.notifier)
        ..setTitle('Ya Rabbi')
        ..setLyrics('Lyrics');

      await _controller(c).submit();

      final problem = _problem(c) as InvalidDraft;
      expect(problem.issues.map((i) => i.field), [DraftField.voice]);
    });

    test('never produces a receipt', () async {
      final c = ProviderContainer(retry: (_, _) => null);
      addTearDown(c.dispose);
      c.read(songDraftProvider.notifier)
        ..setType(SongType.instrumental)
        ..setTitle('Ambient');

      await _controller(c).submit();

      expect(
        c.read(generationControllerProvider),
        isNot(isA<GenerationAccepted>()),
      );
    });

    test('every unconfigured service fails with ServiceNotConfigured', () {
      expect(
        () => const UnconfiguredCreditsRepository().balance(),
        throwsA(isA<ServiceNotConfigured>()),
      );
      expect(
        () => const UnconfiguredLyricsAssistant().write(
          const LyricsRequest(
            theme: 't',
            language: _lang,
            genre: _genre,
            mood: _mood,
          ),
        ),
        throwsA(isA<ServiceNotConfigured>()),
      );
      expect(
        () => const UnconfiguredSongGenerationService().submit(
          const GenerationRequest(
            draft: SongDraft(),
            voiceId: null,
            estimatedCredits: 1,
            idempotencyKey: 'k',
          ),
        ),
        throwsA(isA<ServiceNotConfigured>()),
      );
    });

    test('capabilities and voices are empty, not invented', () async {
      expect(
        (await const UnconfiguredSongGenerationService().capabilities())
            .isAvailable,
        isFalse,
      );
      expect(await const UnconfiguredVoiceRepository().listVoices(), isEmpty);
    });
  });

  group('input validation', () {
    test('an incomplete draft is rejected before any backend call', () async {
      final generation = FakeGenerationService();
      final credits = _SpyCredits(120);
      final c = _container(generation: generation, credits: credits);

      await _controller(c).submit();

      final problem = _problem(c) as InvalidDraft;
      expect(
        problem.issues.map((i) => i.field),
        containsAll([DraftField.title, DraftField.lyrics]),
      );
      expect(credits.calls, 0, reason: 'must not even look at credits');
      expect(generation.submitted, isEmpty);
    });

    test('an engine that cannot do the request is an invalid draft', () async {
      final generation = FakeGenerationService(
        capabilities: const GenerationCapabilities(
          engineName: 'Eng',
          songTypes: {SongType.instrumental},
          languages: {},
          voiceConditioning: false,
          advancedOptionIds: {},
        ),
      );
      final c = _container(generation: generation);
      _fillValidDraft(c);

      await _controller(c).submit();

      final problem = _problem(c) as InvalidDraft;
      expect(problem.issues.any((i) => i.field == DraftField.engine), isTrue);
      expect(generation.submitted, isEmpty);
    });

    test('waits for voices to load instead of blaming the user', () async {
      final c = _container();
      _fillValidDraft(c);
      // Voices have not been read yet: a submit must still see readyOwnVoice.
      await _controller(c).submit();
      expect(c.read(generationControllerProvider), isA<GenerationAccepted>());
    });
  });

  group('engine availability', () {
    test('no engine: refused, and credits are never consulted', () async {
      final credits = _SpyCredits(120);
      final generation = FakeGenerationService(
        capabilities: GenerationCapabilities.none,
      );
      final c = _container(generation: generation, credits: credits);
      _fillValidDraft(c);
      c.read(songDraftProvider.notifier).setType(SongType.instrumental);

      await _controller(c).submit();

      expect(_problem(c), isA<EngineUnavailable>());
      expect(credits.calls, 0);
      expect(generation.submitted, isEmpty);
    });
  });

  group('credit checks', () {
    test('insufficient credits blocks submission', () async {
      final generation = FakeGenerationService();
      final c = _container(
        generation: generation,
        credits: FakeCreditsRepository(0),
      );
      _fillValidDraft(c);

      await _controller(c).submit();

      final problem = _problem(c) as InsufficientCredits;
      expect((problem.balance, problem.required), (0, 1));
      expect(generation.submitted, isEmpty);
    });

    test('exactly enough credits is allowed', () async {
      final c = _container(credits: FakeCreditsRepository(1));
      _fillValidDraft(c);
      await _controller(c).submit();
      expect(c.read(generationControllerProvider), isA<GenerationAccepted>());
    });

    test('an unreadable balance blocks submission with its reason', () async {
      final generation = FakeGenerationService();
      final c = _container(
        generation: generation,
        credits: _SpyCredits(0, error: const ServiceFailure('Billing is down')),
      );
      _fillValidDraft(c);

      await _controller(c).submit();

      final problem = _problem(c) as CreditsUnverified;
      expect(problem.message, 'Billing is down');
      expect(generation.submitted, isEmpty);
    });

    test('a non-AppFailure credit error is also handled', () async {
      final c = _container(credits: _SpyCredits(0, error: StateError('boom')));
      _fillValidDraft(c);
      await _controller(c).submit();
      expect(_problem(c), isA<CreditsUnverified>());
    });
  });

  group('accepted generation', () {
    test('submits one request carrying the draft, voice and cost', () async {
      final generation = FakeGenerationService();
      final credits = FakeCreditsRepository(120);
      final c = _container(generation: generation, credits: credits);
      _fillValidDraft(c);

      await _controller(c).submit();

      final state = c.read(generationControllerProvider);
      expect(state, isA<GenerationAccepted>());
      final receipt = (state as GenerationAccepted).receipt;
      expect(receipt.jobId, 'job-1');
      expect(receipt.creditsReserved, 1);

      expect(generation.submitted, hasLength(1));
      final request = generation.submitted.single;
      expect(request.voiceId, readyOwnVoice.id);
      expect(request.estimatedCredits, 1);
      expect(request.draft.title, 'Ya Rabbi');
      expect(request.idempotencyKey, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('the client itself never debits credits', () async {
      final credits = FakeCreditsRepository(120);
      final c = _container(credits: credits);
      _fillValidDraft(c);

      await _controller(c).submit();

      expect(credits.credits, 120, reason: 'charging is the backend’s job');
    });

    test('an instrumental request carries no voice', () async {
      final generation = FakeGenerationService();
      final c = _container(generation: generation);
      c.read(songDraftProvider.notifier)
        ..setType(SongType.instrumental)
        ..setTitle('Ambient');

      await _controller(c).submit();

      expect(generation.submitted.single.voiceId, isNull);
    });

    test('refreshes the balance after acceptance', () async {
      final credits = _SpyCredits(120);
      final c = _container(credits: credits);
      c.listen(creditBalanceProvider, (_, _) {});
      await c.read(creditBalanceProvider.future);
      final before = credits.calls;
      _fillValidDraft(c);

      await _controller(c).submit();
      await c.read(creditBalanceProvider.future);

      expect(credits.calls, greaterThan(before + 1));
    });
  });

  group('failures after the request is sent', () {
    test(
      'a service failure surfaces its message and nothing is accepted',
      () async {
        final generation = FakeGenerationService(
          failure: const ServiceFailure('Provider is busy'),
        );
        final c = _container(generation: generation);
        _fillValidDraft(c);

        await _controller(c).submit();

        final problem = _problem(c) as SubmitFailed;
        expect(problem.message, 'Provider is busy');
      },
    );

    test(
      'an unexpected error gives an honest message, not a charge claim',
      () async {
        final generation = FakeGenerationService()
          ..unexpectedError = TimeoutException('network');
        final c = _container(generation: generation);
        _fillValidDraft(c);

        await _controller(c).submit();

        final message = (_problem(c) as SubmitFailed).message;
        expect(message, contains('couldn’t confirm'));
        expect(message, isNot(contains('not been charged')));
        expect(
          message,
          isNot(contains('TimeoutException')),
          reason: 'no leaks',
        );
      },
    );
  });

  group('idempotency', () {
    test('a retry of the same request reuses the key', () async {
      final generation = FakeGenerationService(
        failure: const ServiceFailure('Provider is busy'),
      );
      final c = _container(generation: generation);
      _fillValidDraft(c);

      await _controller(c).submit();
      _controller(c).dismiss();
      generation.failure = null;
      await _controller(c).submit();

      expect(generation.submitted, hasLength(2));
      expect(
        generation.submitted[0].idempotencyKey,
        generation.submitted[1].idempotencyKey,
      );
      expect(c.read(generationControllerProvider), isA<GenerationAccepted>());
    });

    test('changing the draft starts a new key', () async {
      final generation = FakeGenerationService(
        failure: const ServiceFailure('busy'),
      );
      final c = _container(generation: generation);
      _fillValidDraft(c);

      await _controller(c).submit();
      _controller(c).dismiss();
      c.read(songDraftProvider.notifier).setTitle('A different title');
      await _controller(c).submit();

      expect(
        generation.submitted[0].idempotencyKey,
        isNot(generation.submitted[1].idempotencyKey),
      );
    });

    test('a new song after a success gets a fresh key', () async {
      final generation = FakeGenerationService();
      final c = _container(generation: generation);
      _fillValidDraft(c);

      await _controller(c).submit();
      _controller(c).dismiss();
      await _controller(c).submit();

      expect(generation.submitted, hasLength(2));
      expect(
        generation.submitted[0].idempotencyKey,
        isNot(generation.submitted[1].idempotencyKey),
      );
    });

    test('a retry after an ambiguous failure keeps the key too', () async {
      final generation = FakeGenerationService()
        ..unexpectedError = TimeoutException('network');
      final c = _container(generation: generation);
      _fillValidDraft(c);

      await _controller(c).submit();
      _controller(c).dismiss();
      generation.unexpectedError = null;
      await _controller(c).submit();

      expect(
        generation.submitted[0].idempotencyKey,
        generation.submitted[1].idempotencyKey,
      );
    });
  });

  group('state transitions', () {
    test('idle → submitting → accepted → idle', () async {
      final generation = FakeGenerationService()
        ..gate = Completer<GenerationReceipt>();
      final c = _container(generation: generation);
      _fillValidDraft(c);
      final seen = <Type>[];
      c.listen(
        generationControllerProvider,
        (_, next) => seen.add(next.runtimeType),
        fireImmediately: true,
      );

      final future = _controller(c).submit();
      await pumpEventQueue();
      expect(c.read(generationControllerProvider), isA<GenerationSubmitting>());

      generation.gate!.complete(
        const GenerationReceipt(
          jobId: 'j',
          status: GenerationStatus.queued,
          creditsReserved: 1,
        ),
      );
      await future;
      _controller(c).dismiss();

      expect(seen, [
        GenerationIdle,
        GenerationSubmitting,
        GenerationAccepted,
        GenerationIdle,
      ]);
    });

    test('a second tap while submitting is ignored', () async {
      final generation = FakeGenerationService()
        ..gate = Completer<GenerationReceipt>();
      final c = _container(generation: generation);
      _fillValidDraft(c);

      final first = _controller(c).submit();
      final second = _controller(c).submit();
      await pumpEventQueue();
      generation.gate!.complete(
        const GenerationReceipt(
          jobId: 'j',
          status: GenerationStatus.processing,
          creditsReserved: 1,
        ),
      );
      await Future.wait([first, second]);

      expect(generation.submitted, hasLength(1), reason: 'no duplicate job');
    });

    test('dismiss is ignored while a submission is in flight', () async {
      final generation = FakeGenerationService()
        ..gate = Completer<GenerationReceipt>();
      final c = _container(generation: generation);
      _fillValidDraft(c);

      final future = _controller(c).submit();
      await pumpEventQueue();
      _controller(c).dismiss();
      expect(c.read(generationControllerProvider), isA<GenerationSubmitting>());

      generation.gate!.complete(
        const GenerationReceipt(
          jobId: 'j',
          status: GenerationStatus.queued,
          creditsReserved: 1,
        ),
      );
      await future;
    });
  });
}

// Constants for the unconfigured-assistant probe above.
const _lang = SongLanguage.hausa;
const _genre = SongGenre.islamicNasheed;
const _mood = SongMood.peaceful;
