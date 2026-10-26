import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:lucide_icons_flutter/lucide_icons_weights.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../core/widgets/deen_icons.dart';
import '../../../core/widgets/section_header.dart';
import '../../../domain/song/song_draft.dart';
import '../../../domain/song/song_options.dart';
import 'field_widgets.dart';

/// Title, language, style, mood, tempo, duration, vocal intensity and
/// instruments. Every control writes to the draft.
class SongDetailsForm extends ConsumerStatefulWidget {
  const SongDetailsForm({super.key, this.titleError});

  final String? titleError;

  @override
  ConsumerState<SongDetailsForm> createState() => _SongDetailsFormState();
}

class _SongDetailsFormState extends ConsumerState<SongDetailsForm> {
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(
      text: ref.read(songDraftProvider).draft.title,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(songDraftProvider.select((s) => s.draft));
    final notifier = ref.read(songDraftProvider.notifier);
    const gold = DeenColors.gold;
    const gap = SizedBox(width: 11);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Song Details', hint: 'Customize your song'),
        const SizedBox(height: 2.4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 444,
              child: ChipLabeledFrame(
                label: 'Song Title',
                hasError: widget.titleError != null,
                child: Semantics(
                  textField: true,
                  label: 'Song title',
                  child: TextField(
                    key: const ValueKey('title-field'),
                    controller: _title,
                    style: DeenText.fieldValue.copyWith(fontSize: 9.5),
                    cursorColor: gold,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        SongDraft.maxTitleLength,
                      ),
                    ],
                    onChanged: notifier.setTitle,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.fromLTRB(13, 12, 10, 8),
                      hintText: 'Enter a title for your song...',
                      hintStyle: DeenText.fieldValue.copyWith(
                        fontSize: 9.5,
                        color: DeenColors.placeholder,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 326,
              child: ChipLabeledSelect<SongLanguage>(
                label: 'Language',
                icon: const Icon(
                  LucideIcons.globe,
                  size: 14,
                  color: Color(0xFFDEE1E4),
                ),
                options: SongLanguage.values,
                selected: draft.language,
                onChanged: notifier.setLanguage,
              ),
            ),
          ],
        ),
        if (widget.titleError != null)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(widget.titleError!, style: DeenText.error),
          ),
        const SizedBox(height: 9.5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 296,
              child: LabeledSelect<SongGenre>(
                label: 'Style / Genre',
                icon: const DomeIcon(color: gold, size: 19),
                options: SongGenre.values,
                selected: draft.genre,
                onChanged: notifier.setGenre,
              ),
            ),
            gap,
            Expanded(
              flex: 229,
              child: LabeledSelect<SongMood>(
                label: 'Mood',
                icon: const Icon(LucideIcons500.heart, size: 15.5, color: gold),
                options: SongMood.values,
                selected: draft.mood,
                onChanged: notifier.setMood,
              ),
            ),
            gap,
            Expanded(
              flex: 225,
              child: LabeledSelect<SongTempo>(
                label: 'Tempo',
                icon: const Icon(LucideIcons500.gauge, size: 15.5, color: gold),
                options: SongTempo.values,
                selected: draft.tempo,
                onChanged: notifier.setTempo,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10.5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 296,
              child: LabeledSelect<SongDuration>(
                label: 'Duration',
                icon: const Icon(LucideIcons500.clock, size: 15.5, color: gold),
                options: SongDuration.values,
                selected: draft.duration,
                onChanged: notifier.setDuration,
              ),
            ),
            gap,
            Expanded(
              flex: 229,
              child: LabeledSelect<VocalIntensity>(
                label: 'Vocal Intensity',
                icon: const BarsIcon(color: gold, size: 15),
                options: VocalIntensity.values,
                selected: draft.intensity,
                onChanged: notifier.setIntensity,
              ),
            ),
            gap,
            Expanded(
              flex: 225,
              child: LabeledSelect<InstrumentSet>(
                label: 'Instruments',
                icon: const Icon(LucideIcons500.music, size: 15.5, color: gold),
                options: InstrumentSet.values,
                selected: draft.instruments,
                onChanged: notifier.setInstruments,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
