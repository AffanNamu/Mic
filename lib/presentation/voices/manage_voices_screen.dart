import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../application/providers.dart';
import '../../core/theme/deen_theme.dart';
import '../../domain/failures.dart';
import '../../domain/voice/voice_profile.dart';
import '../create_song/sheets/add_voice_sheet.dart';
import '../create_song/widgets/voice_selector.dart';
import '../shared/dialogs.dart';

/// Lists the user's voice profiles and lets them delete one.
class ManageVoicesScreen extends ConsumerWidget {
  const ManageVoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voices = ref.watch(voicesProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: DeenColors.background,
        title: Text('Manage Voices', style: DeenText.sheetTitle),
        actions: [
          IconButton(
            tooltip: 'Add New Voice',
            icon: const Icon(LucideIcons.plus),
            onPressed: () => showAddVoiceSheet(context),
          ),
        ],
      ),
      body: voices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(
          text: error is AppFailure
              ? error.message
              : 'Your voices couldn’t be loaded.',
          actionLabel: 'Retry',
          onAction: () => ref.invalidate(voicesProvider),
        ),
        data: (list) => list.isEmpty
            ? _Message(
                text:
                    'You have no saved voices yet. Add a recording of your '
                    'own voice, or of someone who has given you permission, '
                    'to sing your lyrics.',
                actionLabel: 'Add New Voice',
                onAction: () => showAddVoiceSheet(context),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _VoiceTile(voice: list[index]),
              ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: DeenText.body, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _VoiceTile extends ConsumerWidget {
  const _VoiceTile({required this.voice});

  final VoiceProfile voice;

  String get _kind => switch (voice.kind) {
    VoiceKind.own => 'Your voice',
    VoiceKind.authorized => 'Authorized voice',
    VoiceKind.system => 'DeenVoice voice',
  };

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmAction(
      context,
      title: 'Delete ${voice.displayName}?',
      message:
          'This removes the voice from your account and stops it being '
          'used for new songs. Songs you already made are not affected.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ref.read(voiceRepositoryProvider).deleteVoice(voice.id);
      ref.invalidate(voicesProvider);
      if (context.mounted) {
        showMessage(context, '${voice.displayName} was deleted.');
      }
    } on AppFailure catch (e) {
      if (context.mounted) showMessage(context, e.message);
    } catch (_) {
      if (context.mounted) {
        showMessage(context, 'The voice couldn’t be deleted. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: DeenColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeenColors.border, width: 0.75),
      ),
      child: Row(
        children: [
          VoiceAvatar(voice: voice, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(voice.displayName, style: DeenText.bodyStrong),
                Text('$_kind · ${voice.subtitle}', style: DeenText.sectionHint),
              ],
            ),
          ),
          if (voice.kind != VoiceKind.system)
            IconButton(
              tooltip: 'Delete ${voice.displayName}',
              icon: const Icon(LucideIcons.trash2, size: 18),
              color: DeenColors.danger,
              onPressed: () => _delete(context, ref),
            ),
        ],
      ),
    );
  }
}
