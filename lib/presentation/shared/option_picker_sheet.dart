import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/deen_theme.dart';
import '../../domain/song/song_options.dart';

/// Bottom sheet listing [options]; resolves to the chosen one, or null if
/// dismissed.
Future<T?> showOptionPicker<T extends SongOption>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Semantics(
                header: true,
                child: Text(title, style: DeenText.sheetTitle),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  for (final option in options)
                    _OptionTile(
                      option: option,
                      selected: option == selected,
                      onTap: () => Navigator.of(context).pop(option),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SongOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: [option.label, ?option.subtitle].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: DeenText.bodyStrong.copyWith(
                        color: selected
                            ? DeenColors.gold
                            : DeenColors.textPrimary,
                      ),
                    ),
                    if (option.subtitle != null)
                      Text(option.subtitle!, style: DeenText.sectionHint),
                  ],
                ),
              ),
              if (selected)
                const Icon(LucideIcons.check, size: 16, color: DeenColors.gold),
            ],
          ),
        ),
      ),
    );
  }
}
