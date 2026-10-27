import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/deen_theme.dart';

/// The app's language. English is the only one, and the sheet says so rather
/// than offering choices that do nothing.
void showLanguageSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text('App language', style: DeenText.sheetTitle),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DeenColors.selectedFill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DeenColors.goldBorder),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('English', style: DeenText.bodyStrong)),
                  const Icon(
                    LucideIcons.check,
                    size: 18,
                    color: DeenColors.gold,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'DeenVoice is only available in English for now. Your songs can '
              'still have Hausa, Arabic or English lyrics.',
              style: DeenText.body,
            ),
          ],
        ),
      ),
    ),
  );
}
