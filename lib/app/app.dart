import 'package:flutter/material.dart';

import '../core/theme/deen_theme.dart';
import '../presentation/create_song/create_song_screen.dart';

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
      home: const CreateSongScreen(),
    );
  }
}
