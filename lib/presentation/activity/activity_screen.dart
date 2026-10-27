import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/activity.dart';
import '../../application/providers.dart';
import '../../core/format.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/failures.dart';
import '../../domain/library/library.dart';
import '../../domain/voice/voice_profile.dart';
import '../library/song_player_screen.dart';
import '../voices/manage_voices_screen.dart';

/// What has happened to the user's songs and voices, as the server reported it.
/// Opening this screen is what clears the bell.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  /// What was new when the screen opened, so those rows stay marked while the
  /// bell itself clears.
  DateTime? _seenWhenOpened;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(activitySeenProvider, (_, next) {
      if (next.isLoading || _captured) return;
      _captured = true;
      _seenWhenOpened = next.value;
      // Not now: this may be running while the screen is being built, and a
      // provider must not change during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(activitySeenProvider.notifier).markSeen();
      });
    }, fireImmediately: true);
  }

  Future<void> _refresh() async {
    ref.invalidate(recentJobsProvider);
    ref.invalidate(voicesProvider);
    await ref
        .read(recentJobsProvider.future)
        .catchError((_) => <GenerationJob>[]);
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(recentJobsProvider);
    final voices = ref.watch(voicesProvider).value ?? const <VoiceProfile>[];
    final connected = ref.watch(generationJobsProvider) != null;
    final now = ref.read(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: DeenColors.background,
        title: Text('Activity', style: DeenText.sheetTitle),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: !connected
            ? const _Empty(
                'Activity appears here once this build is connected to a '
                'DeenVoice service.',
              )
            : jobs.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _Empty(
                  error is AppFailure
                      ? error.message
                      : 'Your activity couldn’t be loaded.',
                  actionLabel: 'Try again',
                  onAction: () => ref.invalidate(recentJobsProvider),
                ),
                data: (list) {
                  final active = list.where((j) => !j.status.isFinished);
                  final done = list.where((j) => j.status.isFinished);
                  final voiceItems = voices.where(
                    (v) =>
                        v.status == VoiceStatus.enrolling ||
                        v.status == VoiceStatus.failed,
                  );
                  if (list.isEmpty && voiceItems.isEmpty) {
                    return const _Empty(
                      'Nothing yet. When a song finishes, or something needs '
                      'your attention, you’ll see it here.',
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      for (final v in voiceItems) _VoiceRow(voice: v),
                      for (final j in active) _JobRow(job: j, now: now),
                      for (final j in done)
                        _JobRow(
                          job: j,
                          now: now,
                          isNew:
                              (j.status == JobStatus.completed ||
                                  j.status == JobStatus.failed) &&
                              (_seenWhenOpened == null ||
                                  finishedAt(j).isAfter(_seenWhenOpened!)),
                        ),
                    ],
                  );
                },
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text, {this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
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
          ),
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    this.isNew = false,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final bool isNew;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = [if (isNew) 'New.', title, detail].join(' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: onTap != null,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: DeenColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isNew
                  ? DeenColors.goldBorder.withValues(alpha: 0.6)
                  : DeenColors.border,
              width: 0.8,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: DeenText.bodyStrong),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: color == DeenColors.danger
                              ? DeenText.error
                              : DeenText.sectionHint,
                        ),
                      ],
                    ),
                  ),
                  if (isNew)
                    Container(
                      margin: const EdgeInsets.only(top: 4, left: 8),
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: DeenColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.now, this.isNew = false});

  final GenerationJob job;
  final DateTime now;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final when = formatAgo(finishedAt(job), now);
    switch (job.status) {
      case JobStatus.completed:
        return _Row(
          icon: LucideIcons.circleCheck,
          color: const Color(0xFF3DDC84),
          title: '“${job.title}” is ready',
          detail: when,
          isNew: isNew,
          onTap: job.songId == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SongPlayerScreen(songId: job.songId!),
                  ),
                ),
        );
      case JobStatus.failed:
        return _Row(
          icon: LucideIcons.circleAlert,
          color: DeenColors.danger,
          title: '“${job.title}” couldn’t be made',
          detail:
              '${job.failureMessage ?? 'This song could not be made.'} · $when',
          isNew: isNew,
        );
      case JobStatus.cancelled:
        return _Row(
          icon: LucideIcons.circleX,
          color: DeenColors.textMuted,
          title: '“${job.title}” was cancelled',
          detail: when,
        );
      case JobStatus.queued ||
          JobStatus.submitting ||
          JobStatus.processing ||
          JobStatus.downloading:
        return _Row(
          icon: LucideIcons.loader,
          color: DeenColors.gold,
          title: '“${job.title}” is being made',
          detail: job.stage,
        );
    }
  }
}

class _VoiceRow extends StatelessWidget {
  const _VoiceRow({required this.voice});

  final VoiceProfile voice;

  @override
  Widget build(BuildContext context) {
    final failed = voice.status == VoiceStatus.failed;
    return _Row(
      icon: failed ? LucideIcons.micOff : LucideIcons.mic,
      color: failed ? DeenColors.danger : DeenColors.gold,
      title: failed
          ? '${voice.displayName} couldn’t be set up'
          : '${voice.displayName} is being processed',
      detail: failed
          ? (voice.detail ?? 'Open Manage Voices to remove it and try again.')
          : 'It will be ready to use soon.',
      onTap: failed
          ? () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ManageVoicesScreen(),
              ),
            )
          : null,
    );
  }
}
