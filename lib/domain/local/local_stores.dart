import 'package:flutter/foundation.dart';

import '../song/song_draft.dart';

/// Whether the first-run introduction has been seen on this device.
abstract interface class OnboardingStore {
  Future<bool> isCompleted();

  Future<void> markCompleted();
}

/// A song draft kept on this device so work survives closing the app.
@immutable
class SavedDraft {
  const SavedDraft({
    required this.draft,
    required this.savedAt,
    required this.ownerId,
  });

  final SongDraft draft;
  final DateTime savedAt;

  /// The signed-in user the draft belongs to, or null when no backend is
  /// connected. A draft is only ever shown to its owner.
  final String? ownerId;

  /// Worth resuming: the user has written something. A draft that only holds
  /// default selections is not "work".
  bool get hasContent =>
      draft.title.trim().isNotEmpty || draft.lyrics.trim().isNotEmpty;
}

abstract interface class DraftStore {
  Future<SavedDraft?> read();

  Future<void> write(SavedDraft draft);

  Future<void> clear();
}

/// When the user last opened the Activity screen, per account, so the bell can
/// say whether something finished since.
abstract interface class ActivityStore {
  Future<DateTime?> lastSeen(String? ownerId);

  Future<void> markSeen(String? ownerId, DateTime when);

  /// Forget everything (sign-out).
  Future<void> clear();
}
