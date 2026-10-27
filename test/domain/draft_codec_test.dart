import 'package:deenvoice/domain/song/draft_codec.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const full = SongDraft(
    type: SongType.nasheedStyle,
    title: 'Ya Rabbi',
    lyrics: 'Allahu Allah\nSubhanAllah',
    language: SongLanguage.arabic,
    genre: SongGenre.qasida,
    mood: SongMood.solemn,
    tempo: SongTempo.slow,
    duration: SongDuration.fourToFive,
    intensity: VocalIntensity.powerful,
    instruments: InstrumentSet.acoustic,
    voiceId: 'voice-1',
    advanced: {'pitch': 'high'},
  );

  test('every field survives a round trip', () {
    expect(DraftCodec.decode(DraftCodec.encode(full)), full);
    expect(
      DraftCodec.decode(DraftCodec.encode(const SongDraft())),
      const SongDraft(),
    );
  });

  test('is stored by wire id, not by Dart name', () {
    final json = DraftCodec.encode(full);
    expect(json['type'], 'nasheed_style');
    expect(json['genre'], 'qasida');
    expect(json['duration'], '4_5_min');
  });

  test('anything that is not a current-version draft is refused', () {
    expect(DraftCodec.decode(null), isNull);
    expect(DraftCodec.decode('text'), isNull);
    expect(DraftCodec.decode({'v': 99, 'title': 'x'}), isNull);
    expect(DraftCodec.decode({'title': 'no version'}), isNull);
  });

  test('a value this version does not know falls back, keeping the words', () {
    final json = {
      ...DraftCodec.encode(full),
      'language': 'klingon',
      'genre': 7,
      'mood': null,
    };
    final d = DraftCodec.decode(json)!;
    expect(d.language, const SongDraft().language);
    expect(d.genre, const SongDraft().genre);
    expect(d.mood, const SongDraft().mood);
    expect(d.lyrics, full.lyrics);
    expect(d.title, full.title);
  });

  test('over-long text is cut to the limits and wrong types become empty', () {
    final d = DraftCodec.decode({
      ...DraftCodec.encode(full),
      'title': 'a' * 500,
      'lyrics': 'b' * 9000,
    })!;
    expect(d.title.length, SongDraft.maxTitleLength);
    expect(d.lyrics.length, SongDraft.maxLyricsLength);
    final odd = DraftCodec.decode({
      ...DraftCodec.encode(full),
      'title': 12,
      'lyrics': ['x'],
      'voiceId': '',
      'advanced': {'ok': 'yes', 'bad': 3, 4: 'bad'},
    })!;
    expect(odd.title, isEmpty);
    expect(odd.lyrics, isEmpty);
    expect(odd.voiceId, isNull);
    expect(odd.advanced, {'ok': 'yes'});
  });
}
