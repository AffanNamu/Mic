import 'package:flutter/foundation.dart';

/// Where a generation job is, as reported by the backend. The app never
/// invents progress: it shows these states and the server's own wording.
enum JobStatus {
  queued,
  submitting,
  processing,
  downloading,
  completed,
  failed,
  cancelled;

  static JobStatus? fromWire(String? value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }

  bool get isFinished =>
      this == completed || this == failed || this == cancelled;
}

@immutable
class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.status,
    required this.stage,
    required this.title,
    required this.credits,
    required this.createdAt,
    this.failureCode,
    this.failureMessage,
    this.songId,
    this.completedAt,
  });

  final String id;
  final JobStatus status;

  /// Short server-provided label, e.g. "Generating your song".
  final String stage;
  final String title;
  final int credits;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? failureCode;

  /// Plain-language reason from the server, including what happened to the
  /// credits. Shown as-is.
  final String? failureMessage;
  final String? songId;
}

/// A saved song. The audio itself is fetched through [SongLibrary.audio].
@immutable
class SongRecord {
  const SongRecord({
    required this.id,
    required this.title,
    required this.lyrics,
    required this.language,
    required this.provider,
    required this.createdAt,
    this.voiceName,
    this.duration,
  });

  final String id;
  final String title;
  final String lyrics;
  final String language;

  /// The service that produced the audio, shown on the song so it is always
  /// clear what made it.
  final String provider;
  final String? voiceName;
  final Duration? duration;
  final DateTime createdAt;
}

/// A short-lived link the audio player can open without credentials.
@immutable
class SignedAudio {
  const SignedAudio({required this.url, required this.expiresAt});

  final Uri url;
  final DateTime expiresAt;
}

abstract interface class GenerationJobs {
  Future<GenerationJob> job(String jobId);

  /// Recent jobs, newest first.
  Future<List<GenerationJob>> recent();

  /// Only possible before the provider has started the job.
  Future<GenerationJob> cancel(String jobId);
}

abstract interface class SongLibrary {
  Future<List<SongRecord>> list();

  Future<SongRecord> rename(String songId, String title);

  Future<void> delete(String songId);

  Future<SignedAudio> audio(String songId);
}
