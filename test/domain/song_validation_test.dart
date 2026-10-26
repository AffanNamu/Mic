import 'package:deenvoice/domain/generation/generation_capabilities.dart';
import 'package:deenvoice/domain/song/song_draft.dart';
import 'package:deenvoice/domain/song/song_options.dart';
import 'package:deenvoice/domain/song/song_type.dart';
import 'package:deenvoice/domain/song/song_validation.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/fakes.dart' as fakes;

const _complete = SongDraft(title: 'Praise', lyrics: 'Ya Rabbi');

List<DraftField> _fields(List<DraftIssue> issues) =>
    issues.map((i) => i.field).toList();

void main() {
  group('validateDraft', () {
    test('a complete vocal draft with a ready voice is valid', () {
      final issues = validateDraft(
        _complete,
        voices: [readyOwnVoice],
        effectiveVoiceId: readyOwnVoice.id,
      );
      expect(issues, isEmpty);
    });

    test('requires a title, lyrics and a voice for a full song', () {
      final issues = validateDraft(
        const SongDraft(),
        voices: const [],
        effectiveVoiceId: null,
      );
      expect(
        _fields(issues),
        unorderedEquals([
          DraftField.title,
          DraftField.lyrics,
          DraftField.voice,
        ]),
      );
    });

    test('whitespace-only title and lyrics count as empty', () {
      final issues = validateDraft(
        const SongDraft(title: '   ', lyrics: '\n  '),
        voices: [readyOwnVoice],
        effectiveVoiceId: readyOwnVoice.id,
      );
      expect(
        _fields(issues),
        containsAll([DraftField.title, DraftField.lyrics]),
      );
    });

    test('instrumental songs need neither lyrics nor a voice', () {
      final issues = validateDraft(
        const SongDraft(title: 'Ambient', type: SongType.instrumental),
        voices: const [],
        effectiveVoiceId: null,
      );
      expect(issues, isEmpty);
    });

    test('rejects over-long title and lyrics', () {
      final issues = validateDraft(
        SongDraft(
          title: 'x' * (SongDraft.maxTitleLength + 1),
          lyrics: 'y' * (SongDraft.maxLyricsLength + 1),
        ),
        voices: [readyOwnVoice],
        effectiveVoiceId: readyOwnVoice.id,
      );
      expect(
        _fields(issues),
        containsAll([DraftField.title, DraftField.lyrics]),
      );
    });

    test('a voice that cannot sing or is not ready is rejected', () {
      const speechOnly = VoiceProfile(
        id: 'v',
        displayName: 'Speech',
        kind: VoiceKind.own,
        status: VoiceStatus.ready,
        supportsSinging: false,
      );
      const enrolling = VoiceProfile(
        id: 'e',
        displayName: 'New',
        kind: VoiceKind.own,
        status: VoiceStatus.enrolling,
        supportsSinging: true,
      );
      for (final voice in [speechOnly, enrolling]) {
        final issues = validateDraft(
          _complete,
          voices: [voice],
          effectiveVoiceId: voice.id,
        );
        expect(_fields(issues), [DraftField.voice], reason: voice.displayName);
      }
    });

    test('an unknown voice id is treated as no voice', () {
      final issues = validateDraft(
        _complete,
        voices: [readyOwnVoice],
        effectiveVoiceId: 'deleted',
      );
      expect(_fields(issues), [DraftField.voice]);
    });

    group('with an engine connected', () {
      test('flags unsupported song type, language and voice conditioning', () {
        const engine = GenerationCapabilities(
          engineName: 'Eng',
          songTypes: {SongType.instrumental},
          languages: {SongLanguage.english},
          voiceConditioning: false,
          advancedOptionIds: {},
        );
        final issues = validateDraft(
          _complete,
          voices: [readyOwnVoice],
          effectiveVoiceId: readyOwnVoice.id,
          capabilities: engine,
        );
        expect(issues.where((i) => i.field == DraftField.engine), hasLength(3));
      });

      test('passes when the engine supports the request', () {
        final issues = validateDraft(
          _complete,
          voices: [readyOwnVoice],
          effectiveVoiceId: readyOwnVoice.id,
          capabilities: fakes.FakeGenerationService.fullCapabilities,
        );
        expect(issues, isEmpty);
      });
    });
  });

  group('step progress', () {
    test('nothing done: details is the active step', () {
      final done = completedSteps(const SongDraft(), voiceReady: false);
      expect(done, isEmpty);
      expect(activeStep(done), SongStep.details);
    });

    test('advances as the draft is completed', () {
      var done = completedSteps(const SongDraft(title: 'T'), voiceReady: true);
      expect(done, {SongStep.details, SongStep.voiceStyle});
      expect(activeStep(done), SongStep.lyrics);

      done = completedSteps(
        const SongDraft(title: 'T', lyrics: 'L'),
        voiceReady: true,
      );
      expect(activeStep(done), SongStep.generate);
    });

    test('a missing voice keeps Voice & Style open for vocal songs only', () {
      const draft = SongDraft(title: 'T', lyrics: 'L');
      expect(
        activeStep(completedSteps(draft, voiceReady: false)),
        SongStep.voiceStyle,
      );
      expect(
        activeStep(
          completedSteps(
            draft.copyWith(type: SongType.instrumental),
            voiceReady: false,
          ),
        ),
        SongStep.generate,
      );
    });

    test('generate is never reported as completed', () {
      final done = completedSteps(_complete, voiceReady: true);
      expect(done, isNot(contains(SongStep.generate)));
    });
  });

  group('SongDraft', () {
    test('value equality covers the advanced map', () {
      const a = SongDraft(advanced: {'pitch_range': 'low'});
      const b = SongDraft(advanced: {'pitch_range': 'low'});
      const c = SongDraft(advanced: {'pitch_range': 'high'});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('copyWith can clear the voice', () {
      final withVoice = const SongDraft().copyWith(voiceId: 'v');
      expect(withVoice.voiceId, 'v');
      expect(withVoice.copyWith(clearVoice: true).voiceId, isNull);
    });
  });
}
