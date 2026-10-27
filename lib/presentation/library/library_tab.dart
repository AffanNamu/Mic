import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../core/format.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/failures.dart';
import '../../domain/library/library.dart';
import '../create_song/sheets/credits_sheet.dart';
import '../create_song/widgets/credits_pill.dart';
import '../shared/tab_header.dart';
import '../shell/app_shell.dart';
import 'song_player_screen.dart';

/// The user's saved songs, songs still being made, and those that could not
/// be. Everything comes from the backend.
class LibraryTab extends ConsumerWidget {
  const LibraryTab({super.key, required this.onCreate});

  final Future<void> Function() onCreate;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(songsProvider);
    ref.invalidate(recentJobsProvider);
    ref.invalidate(creditBalanceProvider);
    await ref.read(songsProvider.future).catchError((_) => <SongRecord>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(songsProvider);
    final jobs = ref.watch(recentJobsProvider);
    final connected = ref.watch(songLibraryProvider) != null;

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

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabHeader(
            title: 'My Library',
            subtitle: 'Your songs and projects',
            trailing: CreditsPill(onTap: () => showCreditsSheet(context)),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: !connected
                  ? const _Scrollable(
                      child: _Notice(
                        text:
                            'This build isn’t connected to a DeenVoice service, '
                            'so songs can’t be made or saved yet.',
                      ),
                    )
                  : songs.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
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
                        if (list.isEmpty &&
                            inProgress.isEmpty &&
                            failed.isEmpty) {
                          return _Scrollable(
                            child: _Notice(
                              text:
                                  'No songs yet. Create your first song from '
                                  'your lyrics and a voice you’re allowed to '
                                  'use.',
                              actionLabel: 'Create a song',
                              onAction: onCreate,
                            ),
                          );
                        }
                        return ListView(
                          key: const PageStorageKey('library-list'),
                          padding: const EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            shellNavClearance,
                          ),
                          children: [
                            if (inProgress.isNotEmpty) ...[
                              Text('In progress', style: DeenText.sectionTitle),
                              const SizedBox(height: 8),
                              for (final j in inProgress) JobTile(job: j),
                              const SizedBox(height: 16),
                            ],
                            if (failed.isNotEmpty) ...[
                              Text(
                                'Couldn’t be made',
                                style: DeenText.sectionTitle,
                              ),
                              const SizedBox(height: 8),
                              for (final j in failed) JobTile(job: j),
                              const SizedBox(height: 16),
                            ],
                            if (list.isNotEmpty) ...[
                              Text('Your songs', style: DeenText.sectionTitle),
                              const SizedBox(height: 8),
                              for (final s in list) SongTile(song: s),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
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
  const _Notice({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: DeenText.body, textAlign: TextAlign.center),
        if (actionLabel != null) ...[
          const SizedBox(height: 16),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
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

class SongTile extends StatelessWidget {
  const SongTile({super.key, required this.song});

  final SongRecord song;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (song.voiceName != null) song.voiceName!,
      titleCase(song.language),
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

class JobTile extends StatelessWidget {
  const JobTile({super.key, required this.job});

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
