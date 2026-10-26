import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../application/generation_controller.dart';
import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';

/// The primary call to action. Always tappable: a press on an incomplete form
/// explains what is missing rather than silently doing nothing.
class GenerateButton extends ConsumerWidget {
  const GenerateButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy =
        ref.watch(generationControllerProvider) is GenerationSubmitting;
    final credits = ref.watch(estimatedCreditsProvider);
    final cost = credits == 1 ? '1 Credit' : '$credits Credits';
    const radius = BorderRadius.all(Radius.circular(22));

    return Semantics(
      button: true,
      enabled: !busy,
      label: busy
          ? 'Starting your song'
          : 'Generate Song. Costs $credits ${credits == 1 ? 'credit' : 'credits'}.',
      excludeSemantics: true,
      onTap: busy ? null : onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFACB73), Color(0xFFF3B34B)],
          ),
          boxShadow: [
            BoxShadow(
              color: DeenColors.goldDeep.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            splashColor: Colors.white.withValues(alpha: 0.25),
            onTap: busy ? null : onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Symmetric room for the cost on the right, shifted 6pt right
                  // as in the reference; the label scales down rather than
                  // colliding with the cost on narrow screens or big text.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(98, 0, 86, 0),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (busy)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: DeenColors.onGold,
                              ),
                            )
                          else
                            const Icon(
                              LucideIcons.sparkle,
                              size: 20,
                              color: DeenColors.onGold,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            busy ? 'Starting…' : 'Generate Song',
                            style: DeenText.generateLabel,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 19,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          LucideIcons.zap,
                          size: 11,
                          color: DeenColors.onGold,
                        ),
                        const SizedBox(width: 5),
                        Text(cost, style: DeenText.generateCost),
                      ],
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
