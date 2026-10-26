import 'package:flutter/material.dart';

import '../theme/deen_theme.dart';

/// Serif section title with either a right-aligned [hint], or a [trailing]
/// widget (with the hint, if any, placed beside the title).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.hint,
    this.trailing,
    this.titleShift = 0,
  });

  final String title;
  final String? hint;
  final Widget? trailing;

  /// Vertical nudge (pt) for the title and hint relative to the trailing
  /// control, to match the reference where the two are not centred.
  final double titleShift;

  @override
  Widget build(BuildContext context) {
    final hintText = hint == null
        ? null
        : Text(hint!, style: DeenText.sectionHint, maxLines: 2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Transform.translate(
          offset: Offset(0, titleShift),
          child: Semantics(
            header: true,
            child: Text(title, style: DeenText.sectionTitle),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Transform.translate(
              offset: Offset(0, titleShift),
              child: hintText ?? const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
          trailing!,
        ] else ...[
          const SizedBox(width: 8),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: hintText,
            ),
          ),
        ],
      ],
    );
  }
}
