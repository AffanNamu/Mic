import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers.dart';
import '../application/session_controller.dart';
import '../core/theme/deen_theme.dart';
import '../presentation/auth/auth_screen.dart';
import '../presentation/create_song/create_song_screen.dart';
import '../presentation/library/library_home_screen.dart';

class DeenVoiceApp extends StatelessWidget {
  const DeenVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeenVoice',
      debugShowCheckedModeBanner: false,
      theme: buildDeenTheme(),
      builder: (context, child) {
        // Honour the user's text-size setting, but cap it: the reference
        // layout is dense and would break past ~1.3x.
        final scaler = MediaQuery.textScalerOf(context)
            .clamp(minScaleFactor: 1, maxScaleFactor: 1.3);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!,
        );
      },
      home: const _Root(),
    );
  }
}

/// Without a backend (no API_BASE_URL) the app is the unconnected Create Song
/// screen, exactly as before. With one, it requires a signed-in user.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(apiBaseUrlProvider).isEmpty) return const CreateSongScreen();
    final session = ref.watch(sessionProvider);
    return session.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AuthScreen(),
      data: (s) => s == null ? const AuthScreen() : const LibraryHomeScreen(),
    );
  }
}
