/// What kind of output the user wants. The wire `id` is part of the
/// generation contract; do not change it without versioning the API.
enum SongType {
  fullSong(
    id: 'full_song',
    label: 'Full Song',
    description: 'Complete song\nwith vocals & music',
    usesVoice: true,
    usesLyrics: true,
  ),
  vocalOnly(
    id: 'vocal_only',
    label: 'Vocal Only',
    description: 'Only vocals\n(Your voice)',
    usesVoice: true,
    usesLyrics: true,
  ),
  instrumental(
    id: 'instrumental',
    label: 'Instrumental',
    description: 'Background music\nonly',
    usesVoice: false,
    usesLyrics: false,
  ),
  nasheedStyle(
    id: 'nasheed_style',
    label: 'Nasheed Style',
    description: 'Islamic nasheed\ntemplates',
    usesVoice: true,
    usesLyrics: true,
  );

  const SongType({
    required this.id,
    required this.label,
    required this.description,
    required this.usesVoice,
    required this.usesLyrics,
  });

  final String id;
  final String label;
  final String description;

  /// [description] on one line, for screen readers and plain-text uses.
  String get spokenDescription => description.replaceAll('\n', ' ');

  /// Whether a singing voice is part of the output.
  final bool usesVoice;

  /// Whether lyrics are required input.
  final bool usesLyrics;
}
