import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'application/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(
    ProviderScope(
      // Failed loads are shown to the user with a Retry action; they must not
      // silently re-hit the backend.
      retry: (_, _) => null,
      overrides: [
        // Voices being enrolled finish on the server; re-check them while a
        // backend is connected.
        voicePollIntervalProvider.overrideWith(
          (ref) => ref.watch(apiBaseUrlProvider).isEmpty
              ? null
              : const Duration(seconds: 3),
        ),
      ],
      child: const DeenVoiceApp(),
    ),
  );
}
