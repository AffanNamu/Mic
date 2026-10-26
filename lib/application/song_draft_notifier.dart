import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/song/song_draft.dart';
import '../domain/song/song_options.dart';
import '../domain/song/song_type.dart';

/// Draft plus transient UI-facing facts about the last edit.
@immutable
class SongDraftState {
  const SongDraftState({
    this.draft = const SongDraft(),
    this.lyricsTruncated = false,
  });

  final SongDraft draft;

  /// The last imported/generated text was longer than the lyrics limit and was
  /// cut. Cleared by the next edit.
  final bool lyricsTruncated;
}

class SongDraftNotifier extends Notifier<SongDraftState> {
  @override
  SongDraftState build() => const SongDraftState();

  SongDraft get _draft => state.draft;

  void _update(SongDraft draft) => state = SongDraftState(draft: draft);

  /// Switching to Nasheed Style applies its template defaults; other types
  /// only change the type.
  void setType(SongType type) {
    if (type == _draft.type) return;
    if (type == SongType.nasheedStyle) {
      _update(
        _draft.copyWith(
          type: type,
          genre: SongGenre.islamicNasheed,
          mood: SongMood.peaceful,
          instruments: InstrumentSet.traditional,
        ),
      );
    } else {
      _update(_draft.copyWith(type: type));
    }
  }

  void setTitle(String value) => _update(_draft.copyWith(title: value));

  void setLyrics(String value) => _update(_draft.copyWith(lyrics: value));

  /// Replaces lyrics with text from outside the editor (import, AI). Text over
  /// the limit is cut, and [SongDraftState.lyricsTruncated] is set so the UI
  /// can say so.
  void replaceLyrics(String value) {
    final truncated = value.length > SongDraft.maxLyricsLength;
    state = SongDraftState(
      draft: _draft.copyWith(
        lyrics: truncated
            ? value.substring(0, SongDraft.maxLyricsLength)
            : value,
      ),
      lyricsTruncated: truncated,
    );
  }

  void setLanguage(SongLanguage value) =>
      _update(_draft.copyWith(language: value));

  void setGenre(SongGenre value) => _update(_draft.copyWith(genre: value));

  void setMood(SongMood value) => _update(_draft.copyWith(mood: value));

  void setTempo(SongTempo value) => _update(_draft.copyWith(tempo: value));

  void setDuration(SongDuration value) =>
      _update(_draft.copyWith(duration: value));

  void setIntensity(VocalIntensity value) =>
      _update(_draft.copyWith(intensity: value));

  void setInstruments(InstrumentSet value) =>
      _update(_draft.copyWith(instruments: value));

  void selectVoice(String voiceId) =>
      _update(_draft.copyWith(voiceId: voiceId));

  void setAdvanced(String optionId, String value) =>
      _update(_draft.copyWith(advanced: {..._draft.advanced, optionId: value}));
}
