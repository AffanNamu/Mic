import 'song_draft.dart';
import 'song_options.dart';
import 'song_type.dart';

/// Stable JSON form of a [SongDraft] for on-device storage.
///
/// Values are written by wire id, so renaming a Dart enum constant does not
/// invalidate saved drafts. A stored value this version does not know (an
/// older or newer app wrote it) falls back to the field's default rather than
/// discarding the user's words.
abstract final class DraftCodec {
  static const version = 1;

  static Map<String, Object?> encode(SongDraft d) => {
    'v': version,
    'type': d.type.id,
    'title': d.title,
    'lyrics': d.lyrics,
    'language': d.language.id,
    'genre': d.genre.id,
    'mood': d.mood.id,
    'tempo': d.tempo.id,
    'duration': d.duration.id,
    'intensity': d.intensity.id,
    'instruments': d.instruments.id,
    'voiceId': d.voiceId,
    'advanced': d.advanced,
  };

  /// Null when [json] is not a draft at all (wrong shape or version).
  static SongDraft? decode(Object? json) {
    if (json is! Map || json['v'] != version) return null;
    const base = SongDraft();
    T pick<T>(List<T> all, String Function(T) idOf, Object? raw, T fallback) {
      for (final v in all) {
        if (idOf(v) == raw) return v;
      }
      return fallback;
    }

    String text(Object? raw, int max) {
      if (raw is! String) return '';
      return raw.length > max ? raw.substring(0, max) : raw;
    }

    final advanced = <String, String>{};
    final rawAdvanced = json['advanced'];
    if (rawAdvanced is Map) {
      for (final e in rawAdvanced.entries) {
        if (e.key is String && e.value is String) {
          advanced[e.key as String] = e.value as String;
        }
      }
    }
    final voice = json['voiceId'];
    return SongDraft(
      type: pick(SongType.values, (t) => t.id, json['type'], base.type),
      title: text(json['title'], SongDraft.maxTitleLength),
      lyrics: text(json['lyrics'], SongDraft.maxLyricsLength),
      language: pick(
        SongLanguage.values,
        (o) => o.id,
        json['language'],
        base.language,
      ),
      genre: pick(SongGenre.values, (o) => o.id, json['genre'], base.genre),
      mood: pick(SongMood.values, (o) => o.id, json['mood'], base.mood),
      tempo: pick(SongTempo.values, (o) => o.id, json['tempo'], base.tempo),
      duration: pick(
        SongDuration.values,
        (o) => o.id,
        json['duration'],
        base.duration,
      ),
      intensity: pick(
        VocalIntensity.values,
        (o) => o.id,
        json['intensity'],
        base.intensity,
      ),
      instruments: pick(
        InstrumentSet.values,
        (o) => o.id,
        json['instruments'],
        base.instruments,
      ),
      voiceId: voice is String && voice.isNotEmpty ? voice : null,
      advanced: advanced,
    );
  }
}
