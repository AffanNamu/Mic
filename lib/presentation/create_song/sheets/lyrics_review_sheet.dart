import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/text_direction.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../domain/services.dart';

/// Shows an AI suggestion beside the user's own text so nothing is replaced
/// without review. Resolves to true if the user accepts the suggestion.
Future<bool?> showLyricsReviewSheet(
  BuildContext context, {
  required String original,
  required LyricsSuggestion suggestion,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _ReviewSheet(original: original, suggestion: suggestion),
  );
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.original, required this.suggestion});

  final String original;
  final LyricsSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Review suggestion', style: DeenText.sheetTitle),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final note in suggestion.notes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Icon(
                                  LucideIcons.info,
                                  size: 13,
                                  color: DeenColors.gold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(note, style: DeenText.body)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 6),
                      _TextBlock(title: 'Suggested', text: suggestion.lyrics),
                      const SizedBox(height: 12),
                      _TextBlock(title: 'Your lyrics', text: original),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Keep mine'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Use suggestion'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: DeenText.fieldLabel),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: DeenColors.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: DeenColors.borderStrong, width: 0.75),
          ),
          child: SelectableText(
            text,
            textDirection: detectTextDirection(text),
            style: DeenText.input,
          ),
        ),
      ],
    );
  }
}
