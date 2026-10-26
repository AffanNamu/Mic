/// An optional generation setting. Whether it does anything depends on the
/// connected engine; see `GenerationCapabilities.advancedOptionIds`.
class AdvancedOption {
  const AdvancedOption({
    required this.id,
    required this.label,
    required this.choices,
  });

  final String id;
  final String label;

  /// Ordered `(wireValue, label)` pairs. The first is the default.
  final List<(String, String)> choices;

  String get defaultValue => choices.first.$1;
}

/// The catalogue of advanced options DeenVoice knows how to express. Engines
/// declare which of these they honour; the UI only enables those.
const advancedOptionCatalogue = <AdvancedOption>[
  AdvancedOption(
    id: 'pitch_range',
    label: 'Pitch range',
    choices: [
      ('auto', 'Automatic'),
      ('low', 'Low'),
      ('medium', 'Medium'),
      ('high', 'High'),
    ],
  ),
  AdvancedOption(
    id: 'vocal_style',
    label: 'Vocal style',
    choices: [
      ('natural', 'Natural'),
      ('soft', 'Soft'),
      ('powerful', 'Powerful'),
    ],
  ),
  AdvancedOption(
    id: 'arrangement',
    label: 'Arrangement',
    choices: [
      ('standard', 'Standard'),
      ('minimal', 'Minimal'),
      ('layered', 'Layered'),
    ],
  ),
  AdvancedOption(
    id: 'percussion',
    label: 'Percussion',
    choices: [
      ('engine_default', 'Engine default'),
      ('none', 'None'),
      ('daff_only', 'Daff & hand percussion only'),
    ],
  ),
];
