import 'package:flutter/material.dart';

import '../theme/deen_theme.dart';

/// A small outlined pill with an optional leading icon, e.g. "Manage Voices",
/// "Write with AI", "AI Improve".
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.borderColor = DeenColors.goldBorder,
    this.fill,
    this.textStyle,
    this.iconColor,
    this.busy = false,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Color borderColor;
  final Color? fill;
  final TextStyle? textStyle;
  final Color? iconColor;
  final bool busy;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final style = textStyle ?? DeenText.chipLabel;
    final radius = BorderRadius.circular(20);
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: Opacity(
        opacity: onPressed == null ? 0.5 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: radius,
            border: Border.all(color: borderColor, width: 0.75),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: enabled ? onPressed : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 20.5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (busy)
                        const SizedBox(
                          width: 9,
                          height: 9,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.2,
                            color: DeenColors.gold,
                          ),
                        )
                      else
                        ?icon,
                      if (busy || icon != null) const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
