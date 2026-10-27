@Tags(['render'])
library;

import 'package:deenvoice/data/local/memory_stores.dart';
import 'package:deenvoice/domain/library/library.dart';
import 'package:deenvoice/domain/local/local_stores.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes_backend.dart';
import '../support/harness.dart';
import '../support/screen_rig.dart';

/// Renders the Welcome and Home screens in the states the references show and
/// writes them to build/renders/. Compare with tool/compare_render.py.
///
/// The data comes from test doubles purely to reproduce the reference frames
/// (three songs, an unfinished draft, a finished song the user has not seen);
/// the shipped app shows only real data.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('render welcome at reference size', (tester) async {
    await pumpScreens(tester, signedIn: false);
    await savePng(tester, 'build/renders/login.png');
  });

  testWidgets('render home at reference size', (tester) async {
    await pumpScreens(
      tester,
      signedIn: true,
      drafts: MemoryDraftStore(
        SavedDraft(
          draft: const SongDraft(lyrics: 'Ya Rabbi'),
          savedAt: screenNow.subtract(const Duration(hours: 2)),
          ownerId: 'u',
        ),
      ),
      songs: [
        song(
          id: 'a',
          title: 'Ya Rabbi',
          duration: const Duration(minutes: 3, seconds: 42),
        ),
        song(
          id: 'b',
          title: 'Rabbana',
          duration: const Duration(minutes: 4, seconds: 18),
        ),
        song(
          id: 'c',
          title: 'Guide Me',
          duration: const Duration(minutes: 3, seconds: 15),
        ),
      ],
      jobs: [
        GenerationJob(
          id: 'j',
          status: JobStatus.completed,
          stage: 'Ready',
          title: 'Rabbana',
          credits: 1,
          createdAt: screenNow.subtract(const Duration(minutes: 10)),
          completedAt: screenNow.subtract(const Duration(minutes: 5)),
          songId: 'b',
        ),
      ],
    );
    await savePng(tester, 'build/renders/home.png');
  });
}
