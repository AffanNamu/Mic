import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../core/widgets/deen_icons.dart';
import '../../../core/widgets/selectable_card.dart';
import '../../../domain/song/song_type.dart';

/// The four song-type cards. Selection writes straight to the draft.
class SongTypeSelector extends ConsumerWidget {
  const SongTypeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(songDraftProvider.select((s) => s.draft.type));
    final capabilities = ref.watch(capabilitiesProvider).value;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, type) in SongType.values.indexed) ...[
            if (index > 0) const SizedBox(width: 10),
            Expanded(
              child: _SongTypeCard(
                type: type,
                selected: type == selected,
                supported:
                    capabilities == null ||
                    !capabilities.isAvailable ||
                    capabilities.songTypes.contains(type),
                engineName: capabilities?.engineName,
                onTap: () => ref.read(songDraftProvider.notifier).setType(type),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SongTypeCard extends StatelessWidget {
  const _SongTypeCard({
    required this.type,
    required this.selected,
    required this.supported,
    required this.engineName,
    required this.onTap,
  });

  final SongType type;
  final bool selected;
  final bool supported;
  final String? engineName;
  final VoidCallback onTap;

  Widget get _icon => switch (type) {
    SongType.fullSong => Icon(
      LucideIcons500.music,
      size: 20,
      color: DeenColors.gold,
      shadows: _glow(DeenColors.gold),
    ),
    SongType.vocalOnly => Icon(
      LucideIcons500.mic,
      size: 20,
      color: DeenColors.purple,
      shadows: _glow(DeenColors.purple),
    ),
    SongType.instrumental => const OudIcon(color: DeenColors.gold, size: 21),
    SongType.nasheedStyle => Icon(
      LucideIcons500.bookOpenText,
      size: 20,
      color: DeenColors.gold,
      shadows: _glow(DeenColors.gold),
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: supported ? 1 : 0.45,
      child: SelectableCard(
        selected: selected,
        enabled: supported,
        onTap: onTap,
        semanticLabel: supported
            ? '${type.label}. ${type.spokenDescription}'
            : '${type.label}. Not supported by $engineName.',
        padding: const EdgeInsets.fromLTRB(16.5, 10, 3, 7.5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: SizedBox(height: 21, child: _icon),
            ),
            const SizedBox(height: 8),
            Text(type.label, style: DeenText.cardTitle),
            const SizedBox(height: 3),
            Text(
              supported ? type.description : 'Not supported by $engineName',
              style: DeenText.cardDescription,
            ),
          ],
        ),
      ),
    );
  }
}

List<Shadow> _glow(Color color) => [
  Shadow(color: color.withValues(alpha: 0.55), blurRadius: 7),
];
