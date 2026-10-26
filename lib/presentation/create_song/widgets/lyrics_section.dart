import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../application/providers.dart';
import '../../../core/text_direction.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../core/widgets/pill_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/failures.dart';
import '../../../domain/services.dart';
import '../../../domain/song/song_draft.dart';
import '../../shared/dialogs.dart';
import '../sheets/lyrics_review_sheet.dart';
import '../sheets/write_with_ai_sheet.dart';

/// Lyrics editor with Write with AI, Import Text and AI Improve.
class LyricsSection extends ConsumerStatefulWidget {
  const LyricsSection({super.key, this.errorText});

  /// Shown under the box after a failed generate attempt.
  final String? errorText;

  @override
  ConsumerState<LyricsSection> createState() => _LyricsSectionState();
}

class _LyricsSectionState extends ConsumerState<LyricsSection> {
  late final TextEditingController _controller;
  bool _importing = false;
  bool _improving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(songDraftProvider).draft.lyrics,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Busy covers only the file read, not the confirmation dialog after it.
  Future<void> _import() async {
    PickedText? picked;
    setState(() => _importing = true);
    try {
      picked = await ref.read(textFilePickerProvider).pickText();
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, e.message);
      return;
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (picked == null || !mounted) return;

    final text = picked.text.trim();
    if (text.isEmpty) {
      showMessage(context, '“${picked.fileName}” is empty.');
      return;
    }
    if (ref.read(songDraftProvider).draft.lyrics.trim().isNotEmpty) {
      final replace = await confirmAction(
        context,
        title: 'Replace your lyrics?',
        message:
            'Your current lyrics will be replaced by the text in '
            '“${picked.fileName}”.',
        confirmLabel: 'Replace',
      );
      if (!replace || !mounted) return;
    }
    ref.read(songDraftProvider.notifier).replaceLyrics(text);
    if (ref.read(songDraftProvider).lyricsTruncated) {
      showMessage(
        context,
        'Imported text was cut to ${SongDraft.maxLyricsLength} characters.',
      );
    }
  }

  /// Busy covers only the assistant call, not the review sheet after it.
  Future<void> _improve() async {
    final draft = ref.read(songDraftProvider).draft;
    if (draft.lyrics.trim().isEmpty) {
      showMessage(
        context,
        'Add some lyrics first, then AI Improve can refine them.',
      );
      return;
    }
    LyricsSuggestion suggestion;
    setState(() => _improving = true);
    try {
      suggestion = await ref
          .read(lyricsAssistantProvider)
          .improve(lyrics: draft.lyrics, language: draft.language);
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, e.message);
      return;
    } finally {
      if (mounted) setState(() => _improving = false);
    }
    if (!mounted) return;

    final accepted = await showLyricsReviewSheet(
      context,
      original: draft.lyrics,
      suggestion: suggestion,
    );
    if (accepted == true && mounted) {
      ref.read(songDraftProvider.notifier).replaceLyrics(suggestion.lyrics);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(songDraftProvider.select((s) => s.draft.lyrics), (_, next) {
      if (_controller.text != next) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });
    final lyrics = ref.watch(songDraftProvider.select((s) => s.draft.lyrics));
    final hasError = widget.errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Song Lyrics',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PillButton(
                label: 'Write with AI',
                icon: const Icon(
                  LucideIcons.sparkle,
                  size: 11,
                  color: DeenColors.gold,
                ),
                onPressed: () => showWriteWithAiSheet(context),
              ),
              const SizedBox(width: 9),
              PillButton(
                label: 'Import Text',
                borderColor: const Color(0xFF6B5A30),
                busy: _importing,
                icon: const Icon(
                  LucideIcons.fileText,
                  size: 11,
                  color: DeenColors.textPrimary,
                ),
                onPressed: _import,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(minHeight: 96.5),
          padding: const EdgeInsets.fromLTRB(9.5, 4, 9, 8),
          decoration: BoxDecoration(
            color: DeenColors.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasError ? DeenColors.danger : DeenColors.borderStrong,
              width: 0.75,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                textField: true,
                label: 'Song lyrics',
                child: TextField(
                  key: const ValueKey('lyrics-field'),
                  controller: _controller,
                  minLines: 1,
                  maxLines: 12,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  textDirection: detectTextDirection(lyrics),
                  style: DeenText.input,
                  // Forces the 1.7 line height used for painting to also drive
                  // minLines sizing; without it web sizes from the font's
                  // natural line height and the box collapses.
                  strutStyle: const StrutStyle(
                    fontFamily: 'Inter',
                    fontSize: 9.99,
                    height: 1.7,
                    forceStrutHeight: true,
                  ),
                  cursorColor: DeenColors.gold,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(SongDraft.maxLyricsLength),
                  ],
                  onChanged: ref.read(songDraftProvider.notifier).setLyrics,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    // Text-area height stated explicitly (about three 17pt lines) so
                    // the counter row sits at the bottom of the box on every
                    // engine; `minLines` is sized from font metrics that differ
                    // between web and mobile.
                    constraints: const BoxConstraints(minHeight: 59.5),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.fromLTRB(2.5, 3, 4, 3),
                    hintText:
                        'Enter your lyrics here...\n'
                        'You can write in Hausa, Arabic, English or mix languages.',
                    hintStyle: DeenText.inputPlaceholder,
                    hintMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${lyrics.length}/${SongDraft.maxLyricsLength}',
                    style: DeenText.counter,
                  ),
                  const Spacer(),
                  PillButton(
                    label: 'AI Improve',
                    icon: const Icon(
                      LucideIcons.sparkle,
                      size: 11,
                      color: DeenColors.gold,
                    ),
                    textStyle: DeenText.chipLabelGold,
                    borderColor: const Color(0xFF3A4547),
                    fill: const Color(0xFF121D20),
                    busy: _improving,
                    onPressed: _improve,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(widget.errorText!, style: DeenText.error),
          ),
      ],
    );
  }
}
