import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../core/widgets/selectable_card.dart';
import '../../../domain/voice/voice_profile.dart';

/// "Add New Voice" followed by the user's real voice profiles and any system
/// voices the backend offers. Nothing here is hardcoded: with no backend the
/// row shows only the add card.
class VoiceSelector extends ConsumerWidget {
  const VoiceSelector({super.key, required this.onAddVoice});

  final VoidCallback onAddVoice;

  static const double cardHeight = 85.5;
  static const double gap = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voices = ref.watch(voicesProvider);
    final selectedId = ref.watch(selectedVoiceIdProvider);
    final usesVoice = ref.watch(
      songDraftProvider.select((s) => s.draft.type.usesVoice),
    );

    final list = voices.value ?? const <VoiceProfile>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 3 * gap) / 4;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _AddVoiceCard(onTap: onAddVoice),
                    ),
                    for (final voice in list) ...[
                      const SizedBox(width: gap),
                      SizedBox(
                        width: cardWidth,
                        child: Opacity(
                          opacity: usesVoice ? 1 : 0.45,
                          child: _VoiceCard(
                            voice: voice,
                            selected: usesVoice && voice.id == selectedId,
                            onTap: usesVoice
                                ? () => _select(context, ref, voice)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        if (voices.isLoading)
          const _Note('Loading your voices…')
        else if (voices.hasError)
          _Note(
            'Couldn’t load your voices.',
            action: 'Retry',
            onAction: () => ref.invalidate(voicesProvider),
          )
        else if (!usesVoice)
          const _Note('Instrumental songs don’t use a voice.')
        else if (list.isEmpty)
          const _Note(
            'You have no saved voices yet. Add one to sing in your own voice.',
          ),
      ],
    );
  }

  void _select(BuildContext context, WidgetRef ref, VoiceProfile voice) {
    if (!voice.isSelectable) {
      final reason = switch (voice.status) {
        VoiceStatus.enrolling =>
          '${voice.displayName} is still being prepared.',
        VoiceStatus.failed =>
          '${voice.displayName} couldn’t be set up. Open Manage Voices.',
        VoiceStatus.revoked =>
          'Permission for ${voice.displayName} was revoked.',
        VoiceStatus.ready =>
          '${voice.displayName} can’t be used for singing, only speech.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    ref.read(songDraftProvider.notifier).selectVoice(voice.id);
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(text, style: DeenText.sectionHint),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: DeenText.sectionHint.copyWith(
                  color: DeenColors.gold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddVoiceCard extends StatelessWidget {
  const _AddVoiceCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SelectableCard(
      selected: false,
      onTap: onTap,
      semanticLabel: 'Add New Voice. Record or upload.',
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 42.5,
            child: Center(
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0B1718),
                  border: Border.all(
                    color: const Color(0xFF3A4547),
                    width: 0.75,
                  ),
                ),
                child: const Icon(
                  LucideIcons300.plus,
                  size: 22,
                  color: DeenColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Add New Voice',
            style: DeenText.cardTitle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 1.5),
          Text(
            'Record or upload',
            style: DeenText.cardDescription.copyWith(height: 1.2),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VoiceCard extends StatelessWidget {
  const _VoiceCard({
    required this.voice,
    required this.selected,
    required this.onTap,
  });

  final VoiceProfile voice;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: voice.isSelectable ? 1 : 0.6,
      child: SelectableCard(
        selected: selected,
        onTap: onTap,
        enabled: onTap != null,
        semanticLabel: '${voice.displayName}. ${voice.subtitle}.',
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VoiceAvatar(voice: voice, size: 42.5),
            const SizedBox(height: 3),
            Text(
              voice.displayName,
              style: DeenText.cardTitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1.5),
            Text(
              voice.subtitle,
              style: DeenText.cardDescription.copyWith(height: 1.2),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// How an avatar URL becomes an image. Overridable so tests need no network.
final voiceAvatarImageProvider = Provider<ImageProvider Function(String url)>(
  (ref) => NetworkImage.new,
);

/// Round avatar: the profile photo when there is one, a microphone for system
/// voices, otherwise the voice's initial.
class VoiceAvatar extends ConsumerWidget {
  const VoiceAvatar({super.key, required this.voice, required this.size});

  final VoiceProfile voice;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = voice.avatarUrl;
    Widget fallback() {
      if (voice.kind == VoiceKind.system) {
        return Icon(
          LucideIcons300.mic,
          size: size * 0.68,
          color: const Color(0xFFC8CACC),
        );
      }
      final initial = voice.displayName.trim().isEmpty
          ? '?'
          : voice.displayName.trim().characters.first.toUpperCase();
      return Text(
        initial,
        style: DeenText.sectionTitle.copyWith(
          color: DeenColors.gold,
          fontSize: size * 0.42,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2C3D42), Color(0xFF16242A)],
        ),
        border: Border.all(
          color: url == null
              ? const Color(0xFF4A5A5E)
              : const Color(0xFFD5D9DA),
          width: url == null ? 0.75 : 1.2,
        ),
      ),
      child: url == null
          ? fallback()
          : Image(
              image: ref.watch(voiceAvatarImageProvider)(url),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback(),
            ),
    );
  }
}
