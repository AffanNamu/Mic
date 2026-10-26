import 'package:flutter/foundation.dart';

import '../song/song_draft.dart';

/// A validated, engine-neutral request to generate a song.
@immutable
class GenerationRequest {
  const GenerationRequest({
    required this.draft,
    required this.voiceId,
    required this.estimatedCredits,
    required this.idempotencyKey,
  });

  final SongDraft draft;

  /// Null only for song types that do not use a voice.
  final String? voiceId;

  /// What the client expects this to cost. The server is authoritative.
  final int estimatedCredits;

  /// Lets the server collapse retries of the same attempt into one job.
  final String idempotencyKey;
}

enum GenerationStatus { queued, processing }

/// Proof the backend accepted a job.
@immutable
class GenerationReceipt {
  const GenerationReceipt({
    required this.jobId,
    required this.status,
    required this.creditsReserved,
  });

  final String jobId;
  final GenerationStatus status;
  final int creditsReserved;
}
