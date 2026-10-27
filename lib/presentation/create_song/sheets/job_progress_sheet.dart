import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../domain/failures.dart';
import '../../../domain/generation/generation_request.dart';
import '../../../domain/library/library.dart';
import '../../library/song_player_screen.dart';

/// Follows a real job on the server. Everything shown here is what the backend
/// reports; there is no invented percentage or time estimate.
Future<void> showJobProgressSheet(
  BuildContext context,
  GenerationReceipt receipt,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _JobProgressSheet(receipt: receipt),
  );
}

class _JobProgressSheet extends ConsumerStatefulWidget {
  const _JobProgressSheet({required this.receipt});

  final GenerationReceipt receipt;

  @override
  ConsumerState<_JobProgressSheet> createState() => _JobProgressSheetState();
}

class _JobProgressSheetState extends ConsumerState<_JobProgressSheet> {
  bool _cancelling = false;
  String? _cancelError;

  Future<void> _cancel() async {
    setState(() {
      _cancelling = true;
      _cancelError = null;
    });
    try {
      await ref.read(generationJobsProvider)!.cancel(widget.receipt.jobId);
      ref.invalidate(jobWatchProvider(widget.receipt.jobId));
      ref.invalidate(creditBalanceProvider);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _cancelError = e.message);
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.receipt.jobId;
    ref.listen(jobWatchProvider(id), (previous, next) {
      final job = next.value;
      if (job != null && job.status.isFinished) {
        ref.invalidate(songsProvider);
        ref.invalidate(recentJobsProvider);
        ref.invalidate(creditBalanceProvider);
      }
    });
    final watch = ref.watch(jobWatchProvider(id));

    final Widget content = watch.when(
      loading: () => _Status(
        icon: LucideIcons.loader,
        title: 'Starting your song',
        body: '${_credits(widget.receipt.creditsReserved)} reserved.',
        busy: true,
      ),
      error: (error, _) => _Status(
        icon: LucideIcons.wifiOff,
        title: 'Lost contact with DeenVoice',
        body:
            '${error is AppFailure ? error.message : 'The connection failed.'} '
            'Your song may still be in progress. Check My Songs shortly.',
        action: OutlinedButton(
          onPressed: () => ref.invalidate(jobWatchProvider(id)),
          child: const Text('Try again'),
        ),
      ),
      data: (job) => _forJob(context, job),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  (watch.value?.status.isFinished ?? false) ? 'Close' : 'Hide',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _forJob(BuildContext context, GenerationJob job) {
    switch (job.status) {
      case JobStatus.completed:
        return _Status(
          icon: LucideIcons.circleCheck,
          title: 'Your song is ready',
          body: '“${job.title}” was saved to My Songs.',
          action: FilledButton.icon(
            onPressed: job.songId == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SongPlayerScreen(songId: job.songId!),
                      ),
                    );
                  },
            icon: const Icon(LucideIcons.play, size: 16),
            label: const Text('Play'),
          ),
        );
      case JobStatus.failed:
        return _Status(
          icon: LucideIcons.circleAlert,
          title: 'We couldn’t make your song',
          body: job.failureMessage ?? 'The song could not be made.',
          danger: true,
        );
      case JobStatus.cancelled:
        return const _Status(
          icon: LucideIcons.circleX,
          title: 'Cancelled',
          body: 'Nothing was made and your credit was returned.',
        );
      case JobStatus.queued ||
          JobStatus.submitting ||
          JobStatus.processing ||
          JobStatus.downloading:
        return _Status(
          icon: LucideIcons.loader,
          title: job.stage,
          body:
              '${_credits(job.credits)} reserved. You can hide this: the song '
              'keeps being made and appears in My Songs when it’s ready.',
          busy: true,
          action: job.status == JobStatus.queued
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton(
                      onPressed: _cancelling ? null : _cancel,
                      child: Text(_cancelling ? 'Cancelling…' : 'Cancel song'),
                    ),
                    if (_cancelError != null) ...[
                      const SizedBox(height: 6),
                      Text(_cancelError!, style: DeenText.error),
                    ],
                  ],
                )
              : null,
        );
    }
  }

  static String _credits(int n) => '$n ${n == 1 ? 'credit is' : 'credits are'}';
}

class _Status extends StatelessWidget {
  const _Status({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.busy = false,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  final bool busy;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 28,
            color: danger ? DeenColors.danger : DeenColors.gold,
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(title, style: DeenText.sheetTitle),
          ),
          const SizedBox(height: 8),
          Text(body, style: DeenText.body),
          if (busy) ...[
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 3),
          ],
          if (action != null) ...[const SizedBox(height: 14), action!],
        ],
      ),
    );
  }
}
