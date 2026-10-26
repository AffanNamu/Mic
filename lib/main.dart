import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(
    ProviderScope(
      // Failed loads are shown to the user with a Retry action; they must not
      // silently re-hit the backend.
      retry: (_, _) => null,
      child: const DeenVoiceApp(),
    ),
  );
}
