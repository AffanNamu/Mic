import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/providers.dart';
import '../../../core/theme/deen_theme.dart';
import '../../../domain/failures.dart';
import '../../../domain/services.dart';
import '../../shared/dialogs.dart';

Future<void> showWriteWithAiSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _WriteWithAiSheet(),
  );
}

class _WriteWithAiSheet extends ConsumerStatefulWidget {
  const _WriteWithAiSheet();

  @override
  ConsumerState<_WriteWithAiSheet> createState() => _WriteWithAiSheetState();
}

class _WriteWithAiSheetState extends ConsumerState<_WriteWithAiSheet> {
  final _theme = TextEditingController();
  bool _busy = false;
  String? _error;
  LyricsSuggestion? _suggestion;

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  Future<void> _write() async {
    final theme = _theme.text.trim();
    if (theme.isEmpty) {
      setState(() => _error = 'Tell the assistant what the song is about.');
      return;
    }
    final draft = ref.read(songDraftProvider).draft;
    setState(() {
      _busy = true;
      _error = null;
      _suggestion = null;
    });
    try {
      final suggestion = await ref
          .read(lyricsAssistantProvider)
          .write(
            LyricsRequest(
              theme: theme,
              language: draft.language,
              genre: draft.genre,
              mood: draft.mood,
            ),
          );
      if (mounted) setState(() => _suggestion = suggestion);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The lyrics assistant failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _use(LyricsSuggestion suggestion) async {
    final notifier = ref.read(songDraftProvider.notifier);
    if (ref.read(songDraftProvider).draft.lyrics.trim().isNotEmpty) {
      final replace = await confirmAction(
        context,
        title: 'Replace your lyrics?',
        message: 'Your current lyrics will be replaced by the suggestion.',
        confirmLabel: 'Replace',
      );
      if (!replace || !mounted) return;
    }
    notifier.replaceLyrics(suggestion.lyrics);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(songDraftProvider.select((s) => s.draft));
    final suggestion = _suggestion;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Write with AI', style: DeenText.sheetTitle),
              ),
              const SizedBox(height: 6),
              Text(
                'Writing ${draft.language.label} lyrics · ${draft.genre.label}'
                ' · ${draft.mood.label}. Change these in Song Details.',
                style: DeenText.sectionHint,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _theme,
                minLines: 2,
                maxLines: 4,
                enabled: !_busy,
                style: DeenText.input,
                decoration: const InputDecoration(
                  labelText: 'What is the song about?',
                  hintText: 'e.g. gratitude to Allah for daily blessings',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: DeenText.error),
              ],
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _write,
                child: Text(_busy ? 'Writing…' : 'Write lyrics'),
              ),
              if (suggestion != null) ...[
                const SizedBox(height: 16),
                for (final note in suggestion.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('• $note', style: DeenText.body),
                  ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: DeenColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: DeenColors.borderStrong,
                      width: 0.75,
                    ),
                  ),
                  child: SelectableText(
                    suggestion.lyrics,
                    style: DeenText.input,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _suggestion = null),
                        child: const Text('Discard'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _use(suggestion),
                        child: const Text('Use these lyrics'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
