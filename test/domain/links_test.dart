import 'package:deenvoice/domain/links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseWebUrl', () {
    test('accepts http and https pages with a host', () {
      expect(
        parseWebUrl('https://deenvoice.example/terms'),
        Uri.parse('https://deenvoice.example/terms'),
      );
      expect(
        parseWebUrl(' http://example.org/p '),
        Uri.parse('http://example.org/p'),
      );
    });

    test('anything else is not a page the app will offer to open', () {
      for (final raw in [
        '',
        '   ',
        'terms',
        '/terms',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'mailto:a@example.com',
        'ftp://example.org/x',
        'https://',
        'https:///path',
        'data:text/html,<b>x</b>',
      ]) {
        expect(parseWebUrl(raw), isNull, reason: raw);
      }
    });
  });

  test('LegalLinks says whether both documents exist', () {
    final u = Uri.parse('https://example.org/x');
    expect(const LegalLinks().hasBoth, isFalse);
    expect(const LegalLinks().hasAny, isFalse);
    expect(LegalLinks(terms: u).hasBoth, isFalse);
    expect(LegalLinks(terms: u).hasAny, isTrue);
    expect(LegalLinks(terms: u, privacy: u).hasBoth, isTrue);
  });
}
