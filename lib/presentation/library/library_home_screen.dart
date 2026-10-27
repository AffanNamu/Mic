import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../application/session_controller.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/failures.dart';
import '../../domain/library/library.dart';
import '../create_song/create_song_screen.dart';
import '../voices/manage_voices_screen.dart';
import 'song_player_screen.dart';

/// Home for a signed-in user: their saved songs, songs still being made, and
/// the way into Create Song. Everything comes from the backend.
class LibraryHomeScreen extends ConsumerStatefulWidget {
  const LibraryHomeScreen({super.key});

  @override
  ConsumerState<LibraryHomeScreen> createState() => _LibraryHomeScreenState();
}

class _LibraryHomeScreenState extends ConsumerState<LibraryHomeScreen> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// While any job is unfinished, keep asking; stop as soon as none is.
  void _syncPolling(List<GenerationJob> jobs) {
    final active = jobs.any((j) => !j.status.isFinished);
    if (!active) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(ref.read(jobPollIntervalProvider), (_) {
      ref.invalidate(recentJobsProvider);
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(songsProvider);
    ref.invalidate(recentJobsProvider);
    ref.invalidate(creditBalanceProvider);
    await ref.read(songsProvider.future).catchError((_) => <SongRecord>[]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(recentJobsProvider, (previous, next) {
      final jobs = next.value;
      if (jobs == null) return;
      _syncPolling(jobs);
      final before = previous?.value;
      final newlyDone =
          before != null &&
          before.any(
            (b) =>
                !b.status.isFinished &&
                jobs.any((j) => j.id == b.id && j.status.isFinished),
          );
      if (newlyDone) {
        ref.invalidate(songsProvider);
        ref.invalidate(creditBalanceProvider);
      }
    });

    final songs = ref.watch(songsProvider);
    final jobs = ref.watch(recentJobsProvider);
    final email = ref.watch(sessionProvider).value?.email;
    final balance = ref.watch(creditBalanceProvider);

    final now = ref.read(clockProvider)();
    final inProgress = (jobs.value ?? const <GenerationJob>[])
        .where((j) => !j.status.isFinished)
        .toList();
    final failed = (jobs.value ?? const <GenerationJob>[])
        .where(
          (j) =>
              j.status == JobStatus.failed &&
              now.difference(j.createdAt) < const Duration(hours: 24),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: DeenColors.background,
        title: Text('My Songs', style: DeenText.sheetTitle),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Semantics(
                label: 'Credits',
                child: Text(
                  balance.when(
                    data: (n) => '$n ${n == 1 ? 'credit' : 'credits'}',
                    loading: () => '…',
                    error: (_, _) => '– credits',
                  ),
                  style: DeenText.credits,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) async {
              if (value == 'voices') {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ManageVoicesScreen(),
                  ),
                );
              } else if (value == 'signout') {
                await ref.read(sessionProvider.notifier).signOut();
              }
            },
            itemBuilder: (_) => [
              if (email != null)
                PopupMenuItem<String>(enabled: false, child: Text(email)),
              const PopupMenuItem(
                value: 'voices',
                child: Text('Manage voices'),
              ),
              const PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const CreateSongScreen()),
        ),
        icon: const Icon(LucideIcons.sparkles),
        label: const Text('New song'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: songs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _Scrollable(
            child: _Notice(
              text: error is AppFailure
                  ? error.message
                  : 'Your songs couldn’t be loaded.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(songsProvider),
            ),
          ),
          data: (list) {
            if (list.isEmpty && inProgress.isEmpty && failed.isEmpty) {
              return _Scrollable(
                child: _Notice(
                  text:
                      'No songs yet. Create your first song from your lyrics '
                      'and a voice you’re allowed to use.',
                  actionLabel: 'Create a song',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateSongScreen(),
                    ),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                if (inProgress.isNotEmpty) ...[
                  Text('In progress', style: DeenText.sectionTitle),
                  const SizedBox(height: 8),
                  for (final j in inProgress) _JobTile(job: j),
                  const SizedBox(height: 16),
                ],
                if (failed.isNotEmpty) ...[
                  Text('Couldn’t be made', style: DeenText.sectionTitle),
                  const SizedBox(height: 8),
                  for (final j in failed) _JobTile(job: j),
                  const SizedBox(height: 16),
                ],
                if (list.isNotEmpty) ...[
                  Text('Your songs', style: DeenText.sectionTitle),
                  const SizedBox(height: 8),
                  for (final s in list) _SongTile(song: s),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: DeenText.body, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    ),
  );
}

BoxDecoration _tileDecoration({bool danger = false}) => BoxDecoration(
  color: DeenColors.surface,
  borderRadius: BorderRadius.circular(12),
  border: Border.all(
    color: danger
        ? DeenColors.danger.withValues(alpha: 0.5)
        : DeenColors.border,
    width: 0.75,
  ),
);

class _SongTile extends StatelessWidget {
  const _SongTile({required this.song});

  final SongRecord song;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (song.voiceName != null) song.voiceName!,
      song.language,
      if (song.duration != null) formatDuration(song.duration!),
      _date(song.createdAt),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: 'Open ${song.title}',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SongPlayerScreen(songId: song.id),
            ),
          ),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: _tileDecoration(),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, style: DeenText.bodyStrong),
                      const SizedBox(height: 2),
                      Text(parts.join(' · '), style: DeenText.sectionHint),
                    ],
                  ),
                ),
                const Icon(LucideIcons.play, size: 18, color: DeenColors.gold),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job});

  final GenerationJob job;

  @override
  Widget build(BuildContext context) {
    final failed = job.status == JobStatus.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _tileDecoration(danger: failed),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(job.title, style: DeenText.bodyStrong),
            const SizedBox(height: 2),
            Text(
              failed
                  ? (job.failureMessage ?? 'This song could not be made.')
                  : job.stage,
              style: failed ? DeenText.error : DeenText.sectionHint,
            ),
            if (!failed) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(minHeight: 3),
            ],
          ],
        ),
      ),
    );
  }
}
