import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/deen_theme.dart';
import '../../core/widgets/pill_button.dart';
import '../create_song/sheets/add_voice_sheet.dart';
import '../shared/tab_header.dart';
import '../shell/app_shell.dart';
import 'manage_voices_screen.dart';

/// The user's saved voices, and the way to add one: record in the app or upload
/// a file, after confirming consent.
class MyVoiceTab extends StatelessWidget {
  const MyVoiceTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabHeader(
            title: 'My Voice',
            subtitle: 'Record or upload your voice',
            trailing: PillButton(
              label: 'Add New Voice',
              icon: const Icon(
                LucideIcons.plus,
                size: 12,
                color: DeenColors.gold,
              ),
              textStyle: DeenText.chipLabelGold,
              onPressed: () => showAddVoiceSheet(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Only your own voice, or the voice of someone who has agreed, '
              'can be added. You confirm this each time, and you can delete a '
              'voice whenever you like.',
              style: DeenText.sectionHint,
            ),
          ),
          const Expanded(child: VoiceList(bottomPadding: shellNavClearance)),
        ],
      ),
    );
  }
}
