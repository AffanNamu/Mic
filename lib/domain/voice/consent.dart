import 'package:flutter/foundation.dart';

import '../services.dart';

/// The consent wording the server will record. The server owns the text and
/// stores a hash of what was shown, so the app displays it verbatim and sends
/// back only the version.
@immutable
class ConsentStatements {
  const ConsentStatements({required this.version, required this.texts});

  final String version;
  final Map<VoiceOwnership, String> texts;

  String? textFor(VoiceOwnership ownership) => texts[ownership];
}

abstract interface class ConsentSource {
  Future<ConsentStatements> statements();
}
