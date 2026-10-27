import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/library/library.dart';
import 'providers.dart';
import 'session_controller.dart';

/// When the user last opened Activity, on this device. Null until they have.
final activitySeenProvider = AsyncNotifierProvider<ActivitySeen, DateTime?>(
  ActivitySeen.new,
);

class ActivitySeen extends AsyncNotifier<DateTime?> {
  String? get _owner => ref.read(sessionProvider).value?.userId;

  @override
  Future<DateTime?> build() {
    final owner = ref.watch(sessionProvider.select((s) => s.value?.userId));
    return ref.read(activityStoreProvider).lastSeen(owner);
  }

  Future<void> markSeen() async {
    final now = ref.read(clockProvider)();
    state = AsyncData(now);
    await ref.read(activityStoreProvider).markSeen(_owner, now);
  }
}

/// When a job reached its end, as far as the server told us.
DateTime finishedAt(GenerationJob job) => job.completedAt ?? job.createdAt;

/// Songs that finished, or failed, since Activity was last opened. This is the
/// number on the bell; it counts only things the server reported.
final unseenActivityProvider = Provider<int>((ref) {
  final seen = ref.watch(activitySeenProvider);
  if (seen.isLoading) return 0;
  final since = seen.value;
  final jobs = ref.watch(recentJobsProvider).value ?? const <GenerationJob>[];
  return jobs
      .where(
        (j) =>
            (j.status == JobStatus.completed || j.status == JobStatus.failed) &&
            (since == null || finishedAt(j).isAfter(since)),
      )
      .length;
});
