import 'package:flutter/foundation.dart';

import 'song_options.dart';
import 'song_type.dart';

/// The user's in-progress song configuration. Immutable; edited through
/// `SongDraftNotifier`.
@immutable
class SongDraft {
  const SongDraft({
    this.type = SongType.fullSong,
    this.title = '',
    this.lyrics = '',
    this.language = SongLanguage.hausa,
    this.genre = SongGenre.islamicNasheed,
    this.mood = SongMood.peaceful,
    this.tempo = SongTempo.normal,
    this.duration = SongDuration.threeToFour,
    this.intensity = VocalIntensity.balanced,
    this.instruments = InstrumentSet.traditional,
    this.voiceId,
    this.advanced = const {},
  });

  static const maxTitleLength = 80;
  static const maxLyricsLength = 3000;

  final SongType type;
  final String title;
  final String lyrics;
  final SongLanguage language;
  final SongGenre genre;
  final SongMood mood;
  final SongTempo tempo;
  final SongDuration duration;
  final VocalIntensity intensity;
  final InstrumentSet instruments;

  /// Explicit user choice. `null` means "use the default voice, if any".
  final String? voiceId;

  /// Advanced option id → chosen wire value. Only meaningful for options the
  /// connected engine supports.
  final Map<String, String> advanced;

  SongDraft copyWith({
    SongType? type,
    String? title,
    String? lyrics,
    SongLanguage? language,
    SongGenre? genre,
    SongMood? mood,
    SongTempo? tempo,
    SongDuration? duration,
    VocalIntensity? intensity,
    InstrumentSet? instruments,
    String? voiceId,
    bool clearVoice = false,
    Map<String, String>? advanced,
  }) {
    return SongDraft(
      type: type ?? this.type,
      title: title ?? this.title,
      lyrics: lyrics ?? this.lyrics,
      language: language ?? this.language,
      genre: genre ?? this.genre,
      mood: mood ?? this.mood,
      tempo: tempo ?? this.tempo,
      duration: duration ?? this.duration,
      intensity: intensity ?? this.intensity,
      instruments: instruments ?? this.instruments,
      voiceId: clearVoice ? null : (voiceId ?? this.voiceId),
      advanced: advanced ?? this.advanced,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SongDraft &&
      other.type == type &&
      other.title == title &&
      other.lyrics == lyrics &&
      other.language == language &&
      other.genre == genre &&
      other.mood == mood &&
      other.tempo == tempo &&
      other.duration == duration &&
      other.intensity == intensity &&
      other.instruments == instruments &&
      other.voiceId == voiceId &&
      mapEquals(other.advanced, advanced);

  @override
  int get hashCode => Object.hash(
    type,
    title,
    lyrics,
    language,
    genre,
    mood,
    tempo,
    duration,
    intensity,
    instruments,
    voiceId,
    Object.hashAllUnordered(
      advanced.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
