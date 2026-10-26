import 'package:flutter/foundation.dart';

import '../song/song_options.dart';
import '../song/song_type.dart';

/// What the currently connected generation engine verifiably supports.
///
/// Produced by the backend from the routed provider's real capabilities. The
/// UI uses it so settings the engine would ignore are never presented as
/// working.
@immutable
class GenerationCapabilities {
  const GenerationCapabilities({
    required this.engineName,
    required this.songTypes,
    required this.languages,
    required this.voiceConditioning,
    required this.advancedOptionIds,
  });

  /// No engine connected: nothing can be generated.
  static const none = GenerationCapabilities(
    engineName: null,
    songTypes: {},
    languages: {},
    voiceConditioning: false,
    advancedOptionIds: {},
  );

  final String? engineName;
  final Set<SongType> songTypes;
  final Set<SongLanguage> languages;

  /// Whether the engine can sing in a user's saved voice profile.
  final bool voiceConditioning;
  final Set<String> advancedOptionIds;

  bool get isAvailable => engineName != null;
}
