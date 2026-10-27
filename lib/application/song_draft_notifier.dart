import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/local/local_stores.dart';
import '../domain/song/song_draft.dart';
import '../domain/song/song_options.dart';
import '../domain/song/song_template.dart';
import '../domain/song/song_type.dart';
import 'providers.dart';
import 'session_controller.dart';

/// Draft plus transient UI-facing facts about the last edit.
@immutable
class SongDraftState {
  const SongDraftState({
    this.draft = const SongDraft(),
    this.lyricsTruncated = false,
    this.editedAt,
  });

  final SongDraft draft;

  /// When the user last changed the draft; null until they have.
  final DateTime? editedAt;

  /// The last imported/generated text was longer than the lyrics limit and was
  /// cut. Cleared by the next edit.
  final bool lyricsTruncated;
}

/// The draft being edited. It is kept on this device (for its owner only) so
/// closing the app does not lose the user's words.
class SongDraftNotifier extends Notifier<SongDraftState> {
  static const _saveDelay = Duration(milliseconds: 600);

  Timer? _saveTimer;

  /// Counts user edits, so a slow restore never overwrites something typed
  /// while it was reading.
  int _edits = 0;

  /// Counts rebuilds (a different account signed in, or the draft was reset),
  /// so work started for one account is never finished for another.
  int _epoch = 0;

  bool _stale(int epoch) => !ref.mounted || epoch != _epoch;

  @override
  SongDraftState build() {
    _epoch++;
    // A different account gets a different (empty) draft.
    ref.watch(sessionProvider.select((s) => s.value?.userId));
    ref.onDispose(() => _saveTimer?.cancel());
    unawaited(_restore());
    return const SongDraftState();
  }

  SongDraft get _draft => state.draft;

  DateTime get _now => ref.read(clockProvider)();

  void _update(SongDraft draft) {
    _edits++;
    state = SongDraftState(draft: draft, editedAt: _now);
    _scheduleSave();
  }

  /// Who owns local data right now. Null with no backend. With one, null
  /// means signed out, and nothing is restored or saved.
  Future<({bool allowed, String? owner})> _owner() async {
    if (ref.read(apiBaseUrlProvider).isEmpty) {
      return (allowed: true, owner: null);
    }
    final session = await ref.read(sessionProvider.future);
    return (allowed: session != null, owner: session?.userId);
  }

  Future<void> _restore() async {
    final store = ref.read(draftStoreProvider);
    final edits = _edits;
    final epoch = _epoch;
    final who = await _owner();
    if (_stale(epoch)) return;
    final saved = await store.read();
    if (_stale(epoch) || saved == null) return;
    if (!who.allowed || saved.ownerId != who.owner) {
      // Someone else's leftovers, or nobody is signed in: never show them.
      await store.clear();
      return;
    }
    if (_edits != edits || !saved.hasContent) return;
    state = SongDraftState(draft: saved.draft, editedAt: saved.savedAt);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    final epoch = _epoch;
    _saveTimer = Timer(_saveDelay, () => unawaited(_save(epoch)));
  }

  Future<void> _save(int epoch) async {
    final store = ref.read(draftStoreProvider);
    final who = await _owner();
    if (_stale(epoch) || !who.allowed) return;
    final saved = SavedDraft(
      draft: state.draft,
      savedAt: state.editedAt ?? _now,
      ownerId: who.owner,
    );
    await (saved.hasContent ? store.write(saved) : store.clear());
  }

  /// Throws the draft away, here and on disk.
  void discard() {
    _saveTimer?.cancel();
    _edits++;
    state = const SongDraftState();
    unawaited(ref.read(draftStoreProvider).clear());
  }

  /// Starts from a template: only its language and style change. Nothing the
  /// user wrote is touched.
  void applyTemplate(SongTemplate template) {
    _update(
      _draft.copyWith(language: template.language, genre: template.genre),
    );
  }

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
    _edits++;
    state = SongDraftState(
      draft: _draft.copyWith(
        lyrics: truncated
            ? value.substring(0, SongDraft.maxLyricsLength)
            : value,
      ),
      lyricsTruncated: truncated,
      editedAt: _now,
    );
    _scheduleSave();
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
