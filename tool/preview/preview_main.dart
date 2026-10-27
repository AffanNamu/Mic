// VISUAL-VERIFICATION ENTRY POINT. NOT PART OF THE PRODUCT.
//
// Runs the real app with test doubles injected so the screen can be rendered
// in the state shown by the design reference (120 credits; three voices). The
// data below is fictional. Never ship a build made from this file; the shipped
// entry point is lib/main.dart, which shows only real data.
//
//   flutter build web --release --no-web-resources-cdn \
//       -t tool/preview/preview_main.dart -o build/web_preview
//   cp -r test/fixtures/avatars build/web_preview/preview_avatars
import 'package:deenvoice/app/app.dart';
import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/presentation/create_song/create_song_screen.dart';
import 'package:deenvoice/presentation/create_song/widgets/voice_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test/support/fakes.dart';

void main() {
  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        voiceRepositoryProvider.overrideWithValue(
          FakeVoiceRepository(const [
            readyOwnVoice,
            readyAuthorizedVoice,
            readySystemVoice,
          ]),
        ),
        creditsRepositoryProvider.overrideWithValue(FakeCreditsRepository(120)),
        voiceAvatarImageProvider.overrideWithValue(
          (url) => NetworkImage(
            'preview_avatars/'
            '${url == 'avatar-a' ? 'reference_avatar_a' : 'reference_avatar_b'}'
            '.png',
          ),
        ),
      ],
      // This entry point renders the Create Song reference, so it opens that
      // screen directly rather than going through the launch flow.
      child: const DeenVoiceApp(home: CreateSongScreen()),
    ),
  );
}
