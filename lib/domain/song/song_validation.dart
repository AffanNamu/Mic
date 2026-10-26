import '../generation/generation_capabilities.dart';
import '../voice/voice_profile.dart';
import 'song_draft.dart';

/// Where in the form an [DraftIssue] belongs.
enum DraftField { title, lyrics, voice, engine }

class DraftIssue {
  const DraftIssue(this.field, this.message);

  final DraftField field;
  final String message;

  @override
  String toString() => '${field.name}: $message';
}

/// The four stages shown in the progress indicator.
enum SongStep {
  details('Song Details'),
  lyrics('Lyrics'),
  voiceStyle('Voice & Style'),
  generate('Generate');

  const SongStep(this.label);

  final String label;
}

/// Checks a draft against input rules, the available voices, and (when an
/// engine is connected) what that engine supports.
///
/// Pure function: no I/O, no provider calls.
List<DraftIssue> validateDraft(
  SongDraft draft, {
  required List<VoiceProfile> voices,
  required String? effectiveVoiceId,
  GenerationCapabilities capabilities = GenerationCapabilities.none,
}) {
  final issues = <DraftIssue>[];

  final title = draft.title.trim();
  if (title.isEmpty) {
    issues.add(const DraftIssue(DraftField.title, 'Give your song a title.'));
  } else if (title.length > SongDraft.maxTitleLength) {
    issues.add(
      const DraftIssue(
        DraftField.title,
        'Keep the title under ${SongDraft.maxTitleLength} characters.',
      ),
    );
  }

  if (draft.type.usesLyrics) {
    final lyrics = draft.lyrics.trim();
    if (lyrics.isEmpty) {
      issues.add(
        const DraftIssue(
          DraftField.lyrics,
          'Add lyrics, or use Write with AI.',
        ),
      );
    } else if (draft.lyrics.length > SongDraft.maxLyricsLength) {
      issues.add(
        const DraftIssue(
          DraftField.lyrics,
          'Lyrics are limited to ${SongDraft.maxLyricsLength} characters.',
        ),
      );
    }
  }

  if (draft.type.usesVoice) {
    final voice = voices.where((v) => v.id == effectiveVoiceId).firstOrNull;
    if (voice == null) {
      issues.add(
        const DraftIssue(
          DraftField.voice,
          'Choose a voice, or add one with Add New Voice.',
        ),
      );
    } else if (!voice.isSelectable) {
      issues.add(
        DraftIssue(
          DraftField.voice,
          '${voice.displayName} can’t be used for singing yet '
          '(${voice.subtitle.toLowerCase()}).',
        ),
      );
    }
  }

  if (capabilities.isAvailable) {
    final engine = capabilities.engineName;
    if (!capabilities.songTypes.contains(draft.type)) {
      issues.add(
        DraftIssue(
          DraftField.engine,
          '$engine can’t generate “${draft.type.label}” songs.',
        ),
      );
    }
    if (!capabilities.languages.contains(draft.language)) {
      issues.add(
        DraftIssue(
          DraftField.engine,
          '$engine doesn’t support ${draft.language.label} yet.',
        ),
      );
    }
    if (draft.type.usesVoice && !capabilities.voiceConditioning) {
      issues.add(
        DraftIssue(
          DraftField.engine,
          '$engine can’t sing in a saved voice profile.',
        ),
      );
    }
  }

  return issues;
}

/// Which steps the user has finished, derived from the real draft state.
///
/// [generate] is never "completed": it is the action itself.
Set<SongStep> completedSteps(SongDraft draft, {required bool voiceReady}) {
  return {
    if (draft.title.trim().isNotEmpty) SongStep.details,
    if (!draft.type.usesLyrics || draft.lyrics.trim().isNotEmpty)
      SongStep.lyrics,
    if (!draft.type.usesVoice || voiceReady) SongStep.voiceStyle,
  };
}

/// The first unfinished step, or [SongStep.generate] when all are done.
SongStep activeStep(Set<SongStep> completed) {
  for (final step in SongStep.values) {
    if (step == SongStep.generate) return step;
    if (!completed.contains(step)) return step;
  }
  return SongStep.generate;
}
