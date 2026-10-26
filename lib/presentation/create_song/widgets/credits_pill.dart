import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';

/// Credit balance with a gold "+" to top up. Shows the real balance from the
/// credits service; when that is unavailable it says so rather than guessing.
class CreditsPill extends ConsumerWidget {
  const CreditsPill({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(creditBalanceProvider);
    final text = balance.when(
      data: (value) => '$value Credits',
      loading: () => '… Credits',
      error: (_, _) => '– Credits',
    );
    final spoken = balance.when(
      data: (value) => '$value credits available. Open credits.',
      loading: () => 'Loading credit balance. Open credits.',
      error: (_, _) => 'Credit balance unavailable. Open credits.',
    );

    return Semantics(
      button: true,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: const Color(0xFF031110),
        shape: const StadiumBorder(
          side: BorderSide(color: Color(0xFF6B5A30), width: 0.75),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 31,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8.5, 0, 3.5, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.zap, size: 13, color: DeenColors.gold),
                  const SizedBox(width: 6),
                  Text(text, style: DeenText.credits),
                  const SizedBox(width: 10),
                  Container(
                    width: 23.5,
                    height: 23.5,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [DeenColors.goldBright, DeenColors.goldDeep],
                      ),
                    ),
                    child: const Icon(
                      LucideIcons.plus,
                      size: 14,
                      color: DeenColors.onGold,
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
