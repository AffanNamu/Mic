import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/deen_theme.dart';
import '../../../domain/generation/generation_request.dart';

/// Confirms the backend accepted the job. Progress tracking and the song
/// library are not part of this build, so this only reports the receipt.
Future<void> showGenerationAcceptedSheet(
  BuildContext context,
  GenerationReceipt receipt,
) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              LucideIcons.circleCheck,
              size: 28,
              color: DeenColors.gold,
            ),
            const SizedBox(height: 10),
            Semantics(
              header: true,
              child: Text(
                'Your song is in the queue',
                style: DeenText.sheetTitle,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Job ${receipt.jobId} is '
              '${receipt.status == GenerationStatus.queued ? 'queued' : 'processing'}. '
              '${receipt.creditsReserved} '
              '${receipt.creditsReserved == 1 ? 'credit is' : 'credits are'} '
              'reserved for it.',
              style: DeenText.body,
            ),
            const SizedBox(height: 8),
            Text(
              'Live progress and your song library arrive in a later update.',
              style: DeenText.sectionHint,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
