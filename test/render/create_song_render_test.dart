@Tags(['render'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

/// Renders the Create Song screen in the state shown by the reference design
/// (120 credits; My Voice, Sister Aisha and Studio Voice available) and writes
/// it to build/renders/. Compare with tool/compare_render.py.
///
/// The data here comes from test doubles purely to reproduce the reference
/// frame; the shipped app shows only real data.
void main() {
  testWidgets('render create song at reference size', (tester) async {
    await loadAppFonts();
    final env = TestEnv(
      voices: FakeVoiceRepository(const [
        readyOwnVoice,
        readyAuthorizedVoice,
        readySystemVoice,
      ]),
      credits: FakeCreditsRepository(120),
      useReferenceAvatars: true,
    );
    await pumpApp(tester, env);
    await savePng(tester, 'build/renders/create_song.png');
  });
}
