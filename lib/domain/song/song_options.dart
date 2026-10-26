/// A selectable value shown in a picker.
abstract interface class SongOption {
  /// Stable wire value.
  String get id;
  String get label;

  /// Optional second line (shown under the label in pickers and fields).
  String? get subtitle;
}

enum SongLanguage implements SongOption {
  hausa('hausa', 'Hausa'),
  arabic('arabic', 'Arabic'),
  english('english', 'English'),
  mixed('mixed', 'Mixed', 'Hausa · Arabic · English');

  const SongLanguage(this.id, this.label, [this.subtitle]);

  @override
  final String id;
  @override
  final String label;
  @override
  final String? subtitle;
}

enum SongGenre implements SongOption {
  islamicNasheed('islamic_nasheed', 'Islamic Nasheed', 'Traditional & modern'),
  hausaNasheed('hausa_nasheed', 'Hausa Nasheed', 'Traditional & modern'),
  arabicNasheed('arabic_nasheed', 'Arabic Nasheed', 'Spiritual & uplifting'),
  englishNasheed(
    'english_nasheed',
    'English Nasheed',
    'Modern & inspirational',
  ),
  qasida('qasida', 'Qasida', 'Classical devotional poetry');

  const SongGenre(this.id, this.label, this.subtitle);

  @override
  final String id;
  @override
  final String label;
  @override
  final String? subtitle;
}

enum SongMood implements SongOption {
  peaceful('peaceful', 'Peaceful'),
  uplifting('uplifting', 'Uplifting'),
  reflective('reflective', 'Reflective'),
  joyful('joyful', 'Joyful'),
  hopeful('hopeful', 'Hopeful'),
  solemn('solemn', 'Solemn');

  const SongMood(this.id, this.label);

  @override
  final String id;
  @override
  final String label;
  @override
  String? get subtitle => null;
}

enum SongTempo implements SongOption {
  slow('slow', 'Slow'),
  normal('normal', 'Normal'),
  upbeat('upbeat', 'Upbeat');

  const SongTempo(this.id, this.label);

  @override
  final String id;
  @override
  final String label;
  @override
  String? get subtitle => null;
}

enum SongDuration implements SongOption {
  oneToTwo('1_2_min', '1 - 2 minutes', 60, 120),
  twoToThree('2_3_min', '2 - 3 minutes', 120, 180),
  threeToFour('3_4_min', '3 - 4 minutes', 180, 240),
  fourToFive('4_5_min', '4 - 5 minutes', 240, 300);

  const SongDuration(this.id, this.label, this.minSeconds, this.maxSeconds);

  @override
  final String id;
  @override
  final String label;
  final int minSeconds;
  final int maxSeconds;
  @override
  String? get subtitle => null;
}

enum VocalIntensity implements SongOption {
  gentle('gentle', 'Gentle'),
  balanced('balanced', 'Balanced'),
  powerful('powerful', 'Powerful');

  const VocalIntensity(this.id, this.label);

  @override
  final String id;
  @override
  final String label;
  @override
  String? get subtitle => null;
}

enum InstrumentSet implements SongOption {
  traditional('traditional', 'Traditional'),
  acoustic('acoustic', 'Acoustic'),
  modern('modern', 'Modern'),
  vocalsOnly('vocals_only', 'Vocals only');

  const InstrumentSet(this.id, this.label);

  @override
  final String id;
  @override
  final String label;
  @override
  String? get subtitle => null;
}
