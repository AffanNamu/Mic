import 'song_options.dart';

/// A starting point on Home: a language and style, nothing more. Applying one
/// never touches the user's title or lyrics.
enum SongTemplate {
  hausaNasheed(SongLanguage.hausa, SongGenre.hausaNasheed),
  arabicNasheed(SongLanguage.arabic, SongGenre.arabicNasheed),
  englishNasheed(SongLanguage.english, SongGenre.englishNasheed),
  mixedLanguage(SongLanguage.mixed, SongGenre.islamicNasheed);

  const SongTemplate(this.language, this.genre);

  final SongLanguage language;
  final SongGenre genre;

  /// "Mixed Language" is the one template whose name is not its genre's.
  String get label => this == mixedLanguage ? 'Mixed Language' : genre.label;

  /// Second line, e.g. "Traditional & modern".
  String get subtitle =>
      this == mixedLanguage ? SongLanguage.mixed.subtitle! : genre.subtitle!;
}
