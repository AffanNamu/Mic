import 'package:deenvoice/core/text_direction.dart';
import 'package:deenvoice/domain/voice/voice_profile.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

VoiceProfile _voice({
  VoiceKind kind = VoiceKind.own,
  VoiceStatus status = VoiceStatus.ready,
  bool sings = true,
  VoicePresentation? presentation,
}) => VoiceProfile(
  id: 'v',
  displayName: 'V',
  kind: kind,
  status: status,
  supportsSinging: sings,
  presentation: presentation,
);

void main() {
  group('VoiceProfile', () {
    test('is selectable only when ready and able to sing', () {
      expect(_voice().isSelectable, isTrue);
      expect(_voice(sings: false).isSelectable, isFalse);
      for (final s in [
        VoiceStatus.enrolling,
        VoiceStatus.failed,
        VoiceStatus.revoked,
      ]) {
        expect(_voice(status: s).isSelectable, isFalse, reason: '$s');
      }
    });

    test('subtitle tells the truth about state before kind', () {
      expect(_voice(status: VoiceStatus.enrolling).subtitle, 'Processing…');
      expect(_voice(status: VoiceStatus.failed).subtitle, 'Enrollment failed');
      expect(
        _voice(status: VoiceStatus.revoked).subtitle,
        'Permission revoked',
      );
      expect(_voice(sings: false).subtitle, 'Speech only');
    });

    test('subtitle describes a ready voice by kind', () {
      expect(_voice().subtitle, 'Personal voice');
      expect(_voice(kind: VoiceKind.system).subtitle, 'AI generated');
      expect(
        _voice(
          kind: VoiceKind.authorized,
          presentation: VoicePresentation.female,
        ).subtitle,
        'Female voice',
      );
      expect(_voice(kind: VoiceKind.authorized).subtitle, 'Authorized voice');
    });
  });

  group('detectTextDirection', () {
    test('Arabic is right-to-left', () {
      expect(detectTextDirection('يا رب'), TextDirection.rtl);
    });
    test('Hausa and English are left-to-right', () {
      expect(detectTextDirection('Ya Allah, ka ji mu'), TextDirection.ltr);
      expect(detectTextDirection('Praise be'), TextDirection.ltr);
    });
    test('the first strong letter wins, skipping digits and punctuation', () {
      expect(detectTextDirection('1) ... يا رب Allah'), TextDirection.rtl);
      expect(detectTextDirection('«Allah» يا'), TextDirection.ltr);
    });
    test('no letters means no opinion', () {
      expect(detectTextDirection(''), isNull);
      expect(detectTextDirection('123 ...'), isNull);
    });
  });
}
