import 'package:flutter/material.dart';

import '../../core/theme/deen_theme.dart';

/// Title row for the bottom-bar tabs: a serif title, a one-line hint, and an
/// optional control on the right.
class TabHeader extends StatelessWidget {
  const TabHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: DeenText.screenTitle.copyWith(fontSize: 24),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: DeenText.screenSubtitle),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
