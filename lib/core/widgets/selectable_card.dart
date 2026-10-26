import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';

import '../theme/deen_theme.dart';

/// A dark rounded card that shows the gold border, glow and check badge when
/// selected. Used for song types and voices.
class SelectableCard extends StatelessWidget {
  const SelectableCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    required this.semanticLabel,
    this.enabled = true,
    this.radius = 11,
    this.padding = EdgeInsets.zero,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final String semanticLabel;
  final bool enabled;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: selected ? null : DeenColors.surface,
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [Color(0xFF2A2C1C), Color(0xFF181F1A)],
                )
              : null,
          border: Border.all(
            color: selected ? DeenColors.goldBorder : DeenColors.border,
            width: 1,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: DeenColors.gold.withValues(alpha: 0.34),
                blurRadius: 14,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: enabled ? onTap : null,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                Padding(padding: padding, child: child),
                if (selected)
                  const Positioned(top: 3.25, right: 2.75, child: CheckBadge()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CheckBadge extends StatelessWidget {
  const CheckBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15.5,
      height: 15.5,
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
        LucideIcons500.check,
        size: 10.5,
        color: DeenColors.onGold,
      ),
    );
  }
}
