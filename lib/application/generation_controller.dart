import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/credits/pricing.dart';
import '../domain/failures.dart';
import '../domain/generation/generation_capabilities.dart';
import '../domain/generation/generation_request.dart';
import '../domain/song/song_draft.dart';
import '../domain/song/song_validation.dart';
import '../domain/voice/voice_profile.dart';
import 'providers.dart';

/// Why a generation did not start. Each case maps to a distinct UI response.
sealed class GenerationProblem {
  const GenerationProblem();
}

final class InvalidDraft extends GenerationProblem {
  const InvalidDraft(this.issues);

  final List<DraftIssue> issues;
}

final class EngineUnavailable extends GenerationProblem {
  const EngineUnavailable();
}

final class CreditsUnverified extends GenerationProblem {
  const CreditsUnverified(this.message);

  final String message;
}

final class InsufficientCredits extends GenerationProblem {
  const InsufficientCredits({required this.balance, required this.required});

  final int balance;
  final int required;
}

final class SubmitFailed extends GenerationProblem {
  const SubmitFailed(this.message);

  final String message;
}

sealed class GenerationUiState {
  const GenerationUiState();
}

final class GenerationIdle extends GenerationUiState {
  const GenerationIdle();
}

final class GenerationSubmitting extends GenerationUiState {
  const GenerationSubmitting();
}

final class GenerationAccepted extends GenerationUiState {
  const GenerationAccepted(this.receipt);

  final GenerationReceipt receipt;
}

final class GenerationRejected extends GenerationUiState {
  const GenerationRejected(this.problem);

  final GenerationProblem problem;
}

final generationControllerProvider =
    NotifierProvider<GenerationController, GenerationUiState>(
      GenerationController.new,
    );

class GenerationController extends Notifier<GenerationUiState> {
  /// Reused for retries of an identical request so the server can collapse
  /// them into one job; replaced as soon as the request changes or succeeds.
  ({int fingerprint, String key})? _attempt;

  @override
  GenerationUiState build() => const GenerationIdle();

  void dismiss() {
    if (state is! GenerationSubmitting) state = const GenerationIdle();
  }

  /// Validates, checks the engine and the balance, then submits one job.
  ///
  /// The client never debits credits: it only checks that the balance covers
  /// the estimate. Charging happens on the backend when it accepts the job,
  /// and the backend must treat [GenerationRequest.idempotencyKey] as the
  /// identity of the job so that retries cannot start or charge twice.
  Future<void> submit() async {
    // Engage the guard before the first await so a fast second tap is ignored.
    if (state is GenerationSubmitting) return;
    state = const GenerationSubmitting();

    final draft = ref.read(songDraftProvider).draft;

    // Wait for what validation depends on: judging a draft against a voice
    // list that has not loaded yet would blame the user for a race.
    final voices = await _voices();
    final capabilities = await _capabilities();
    final voiceId = ref.read(selectedVoiceIdProvider);

    final issues = validateDraft(
      draft,
      voices: voices,
      effectiveVoiceId: voiceId,
      capabilities: capabilities,
    );
    if (issues.isNotEmpty) {
      state = GenerationRejected(InvalidDraft(issues));
      return;
    }
    if (!capabilities.isAvailable) {
      state = const GenerationRejected(EngineUnavailable());
      return;
    }

    final cost = estimateCredits(draft);
    final int balance;
    try {
      balance = await ref.read(creditsRepositoryProvider).balance();
    } on AppFailure catch (e) {
      state = GenerationRejected(CreditsUnverified(e.message));
      return;
    } catch (_) {
      state = const GenerationRejected(
        CreditsUnverified('The credit service did not respond.'),
      );
      return;
    }
    if (balance < cost) {
      state = GenerationRejected(
        InsufficientCredits(balance: balance, required: cost),
      );
      return;
    }

    final request = GenerationRequest(
      draft: draft,
      voiceId: draft.type.usesVoice ? voiceId : null,
      estimatedCredits: cost,
      idempotencyKey: _keyFor(draft, voiceId),
    );
    try {
      final receipt = await ref
          .read(songGenerationServiceProvider)
          .submit(request);
      _attempt = null;
      ref.invalidate(creditBalanceProvider);
      state = GenerationAccepted(receipt);
    } on AppFailure catch (e) {
      state = GenerationRejected(SubmitFailed(e.message));
    } catch (e, stack) {
      // The request may or may not have reached the server, so say only what
      // is true and keep the idempotency key for the retry.
      debugPrint('Unexpected generation error: $e\n$stack');
      state = const GenerationRejected(
        SubmitFailed(
          'We couldn’t confirm that your song was started. Check your '
          'connection and try again. Retrying the same request will not '
          'start a second song.',
        ),
      );
    }
  }

  Future<List<VoiceProfile>> _voices() async {
    try {
      return await ref.read(voicesProvider.future);
    } catch (_) {
      return const [];
    }
  }

  /// Re-asked on every submit: what the engine supports can change during a
  /// session, and a stale answer would submit an unsupported job.
  Future<GenerationCapabilities> _capabilities() async {
    try {
      return await ref.refresh(capabilitiesProvider.future);
    } catch (_) {
      return GenerationCapabilities.none;
    }
  }

  String _keyFor(SongDraft draft, String? voiceId) {
    final fingerprint = Object.hash(draft, voiceId);
    final current = _attempt;
    if (current != null && current.fingerprint == fingerprint) {
      return current.key;
    }
    final random = Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _attempt = (fingerprint: fingerprint, key: key);
    return key;
  }
}
