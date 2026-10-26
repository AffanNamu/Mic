import 'package:deenvoice/application/providers.dart';
import 'package:deenvoice/application/song_draft_notifier.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:deenvoice/domain/song/song_validation.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _enrollingOwn = VoiceProfile(
  id: 'voice-new',
  displayName: 'Processing',
  kind: VoiceKind.own,
  status: VoiceStatus.enrolling,
  supportsSinging: true,
);

Future<ProviderContainer> _container(List<VoiceProfile> voices) async {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      voiceRepositoryProvider.overrideWithValue(FakeVoiceRepository(voices)),
    ],
  );
  addTearDown(c.dispose);
  c.listen(selectedVoiceIdProvider, (_, _) {});
  await c.read(voicesProvider.future);
  return c;
}

void main() {
  group('selectedVoiceIdProvider', () {
    test('defaults to the first ready personal voice', () async {
      final c = await _container([
        readySystemVoice,
        _enrollingOwn,
        readyAuthorizedVoice,
        readyOwnVoice,
      ]);
      expect(c.read(selectedVoiceIdProvider), readyOwnVoice.id);
    });

    test('never defaults to a system or authorized voice', () async {
      final c = await _container([readySystemVoice, readyAuthorizedVoice]);
      expect(c.read(selectedVoiceIdProvider), isNull);
    });

    test('never defaults to a voice that is still enrolling', () async {
      final c = await _container([_enrollingOwn]);
      expect(c.read(selectedVoiceIdProvider), isNull);
    });

    test('an explicit pick wins over the default', () async {
      final c = await _container([readyOwnVoice, readyAuthorizedVoice]);
      c.read(songDraftProvider.notifier).selectVoice(readyAuthorizedVoice.id);
      expect(c.read(selectedVoiceIdProvider), readyAuthorizedVoice.id);
    });

    test('a pick that no longer exists falls back to the default', () async {
      final c = await _container([readyOwnVoice]);
      c.read(songDraftProvider.notifier).selectVoice('deleted-voice');
      expect(c.read(selectedVoiceIdProvider), readyOwnVoice.id);
    });

    test('with no voices at all there is no selection', () async {
      final c = await _container(const []);
      expect(c.read(selectedVoiceIdProvider), isNull);
    });
  });

  group('stepProgressProvider', () {
    test('follows the draft from details to generate', () async {
      final c = await _container([readyOwnVoice]);
      c.listen(stepProgressProvider, (_, _) {});
      final draft = c.read(songDraftProvider.notifier);

      expect(c.read(stepProgressProvider).active, SongStep.details);
      draft.setTitle('Ya Rabbi');
      expect(c.read(stepProgressProvider).active, SongStep.lyrics);
      draft.setLyrics('words');
      expect(c.read(stepProgressProvider).active, SongStep.generate);
    });

    test('without a usable voice, Voice & Style stays open', () async {
      final c = await _container(const []);
      c.listen(stepProgressProvider, (_, _) {});
      c.read(songDraftProvider.notifier)
        ..setTitle('T')
        ..setLyrics('L');
      expect(c.read(stepProgressProvider).active, SongStep.voiceStyle);
    });
  });

  group('SongDraftNotifier', () {
    late ProviderContainer c;
    late SongDraftNotifier notifier;

    setUp(() {
      c = ProviderContainer(retry: (_, _) => null);
      addTearDown(c.dispose);
      notifier = c.read(songDraftProvider.notifier);
    });

    SongDraft draft() => c.read(songDraftProvider).draft;

    test('starts with the reference defaults and nothing invented', () {
      expect(draft().type, SongType.fullSong);
      expect(draft().language, SongLanguage.hausa);
      expect(draft().genre, SongGenre.islamicNasheed);
      expect(draft().mood, SongMood.peaceful);
      expect(draft().tempo, SongTempo.normal);
      expect(draft().duration, SongDuration.threeToFour);
      expect(draft().intensity, VocalIntensity.balanced);
      expect(draft().instruments, InstrumentSet.traditional);
      expect(draft().title, isEmpty);
      expect(draft().lyrics, isEmpty);
      expect(draft().voiceId, isNull);
    });

    test('every setter updates the draft', () {
      notifier
        ..setTitle('T')
        ..setLanguage(SongLanguage.arabic)
        ..setGenre(SongGenre.qasida)
        ..setMood(SongMood.joyful)
        ..setTempo(SongTempo.upbeat)
        ..setDuration(SongDuration.oneToTwo)
        ..setIntensity(VocalIntensity.powerful)
        ..setInstruments(InstrumentSet.vocalsOnly)
        ..selectVoice('v1')
        ..setAdvanced('pitch_range', 'low');
      final d = draft();
      expect(d.title, 'T');
      expect(d.language, SongLanguage.arabic);
      expect(d.genre, SongGenre.qasida);
      expect(d.mood, SongMood.joyful);
      expect(d.tempo, SongTempo.upbeat);
      expect(d.duration, SongDuration.oneToTwo);
      expect(d.intensity, VocalIntensity.powerful);
      expect(d.instruments, InstrumentSet.vocalsOnly);
      expect(d.voiceId, 'v1');
      expect(d.advanced, {'pitch_range': 'low'});
    });

    test('Nasheed Style applies its template; other types only switch', () {
      notifier
        ..setGenre(SongGenre.qasida)
        ..setMood(SongMood.joyful)
        ..setInstruments(InstrumentSet.modern)
        ..setType(SongType.vocalOnly);
      expect(draft().genre, SongGenre.qasida, reason: 'untouched');

      notifier.setType(SongType.nasheedStyle);
      expect(draft().genre, SongGenre.islamicNasheed);
      expect(draft().mood, SongMood.peaceful);
      expect(draft().instruments, InstrumentSet.traditional);
    });

    test('replaceLyrics truncates over-long text and says so', () {
      notifier.replaceLyrics('a' * (SongDraft.maxLyricsLength + 50));
      expect(draft().lyrics.length, SongDraft.maxLyricsLength);
      expect(c.read(songDraftProvider).lyricsTruncated, isTrue);
    });

    test('the truncation notice clears on the next edit', () {
      notifier.replaceLyrics('a' * (SongDraft.maxLyricsLength + 1));
      notifier.setLyrics('short');
      expect(c.read(songDraftProvider).lyricsTruncated, isFalse);
    });

    test('replaceLyrics keeps text within the limit as is', () {
      notifier.replaceLyrics('fits');
      expect(draft().lyrics, 'fits');
      expect(c.read(songDraftProvider).lyricsTruncated, isFalse);
    });
  });
}
