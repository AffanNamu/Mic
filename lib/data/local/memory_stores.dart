import '../../domain/local/local_stores.dart';

/// In-memory stores for tests and runs where nothing should persist.

class MemoryOnboardingStore implements OnboardingStore {
  MemoryOnboardingStore({this.completed = false});

  bool completed;

  @override
  Future<bool> isCompleted() async => completed;

  @override
  Future<void> markCompleted() async => completed = true;
}

class MemoryDraftStore implements DraftStore {
  MemoryDraftStore([this.saved]);

  SavedDraft? saved;
  int writes = 0;

  @override
  Future<SavedDraft?> read() async => saved;

  @override
  Future<void> write(SavedDraft draft) async {
    writes++;
    saved = draft;
  }

  @override
  Future<void> clear() async => saved = null;
}

class MemoryActivityStore implements ActivityStore {
  final _seen = <String?, DateTime>{};

  @override
  Future<DateTime?> lastSeen(String? ownerId) async => _seen[ownerId];

  @override
  Future<void> markSeen(String? ownerId, DateTime when) async =>
      _seen[ownerId] = when;

  @override
  Future<void> clear() async => _seen.clear();
}
