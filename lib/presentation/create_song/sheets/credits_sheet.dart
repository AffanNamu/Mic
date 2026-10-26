import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../domain/failures.dart';

Future<void> showCreditsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _CreditsSheet(),
  );
}

class _CreditsSheet extends ConsumerWidget {
  const _CreditsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(creditBalanceProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('Credits', style: DeenText.sheetTitle),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(LucideIcons.zap, size: 22, color: DeenColors.gold),
                const SizedBox(width: 10),
                Expanded(
                  child: balance.when(
                    data: (value) => Text(
                      '$value ${value == 1 ? 'credit' : 'credits'} available',
                      style: DeenText.sheetTitle.copyWith(
                        color: DeenColors.gold,
                      ),
                    ),
                    loading: () => Text('Loading…', style: DeenText.body),
                    error: (error, _) => Text(
                      error is AppFailure
                          ? error.message
                          : 'Your balance couldn’t be loaded.',
                      style: DeenText.body,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Each song generation uses credits. Buying more credits isn’t '
              'available in this build yet.',
              style: DeenText.body,
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => ref.invalidate(creditBalanceProvider),
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('Refresh balance'),
                style: TextButton.styleFrom(foregroundColor: DeenColors.gold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
