import 'package:deenvoice/core/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 27, 12);

  group('formatAgo', () {
    test('says how long ago, in the unit a person would use', () {
      expect(formatAgo(now, now), 'just now');
      expect(
        formatAgo(now.subtract(const Duration(seconds: 59)), now),
        'just now',
      );
      expect(
        formatAgo(now.subtract(const Duration(minutes: 1)), now),
        '1 minute ago',
      );
      expect(
        formatAgo(now.subtract(const Duration(minutes: 5)), now),
        '5 minutes ago',
      );
      expect(
        formatAgo(now.subtract(const Duration(minutes: 59)), now),
        '59 minutes ago',
      );
      expect(
        formatAgo(now.subtract(const Duration(hours: 1)), now),
        '1 hour ago',
      );
      expect(
        formatAgo(now.subtract(const Duration(hours: 2)), now),
        '2 hours ago',
      );
      expect(
        formatAgo(now.subtract(const Duration(hours: 23)), now),
        '23 hours ago',
      );
      expect(
        formatAgo(now.subtract(const Duration(hours: 24)), now),
        'yesterday',
      );
      expect(
        formatAgo(now.subtract(const Duration(days: 3)), now),
        '3 days ago',
      );
    });

    test('a week or more is a date', () {
      final then = DateTime.utc(2026, 10, 10, 12);
      expect(formatAgo(then, now), matches(RegExp(r'^2026-10-(09|10|11)$')));
    });

    test('a time in the future is "just now", never negative', () {
      expect(formatAgo(now.add(const Duration(hours: 1)), now), 'just now');
    });
  });

  test('formatDuration is m:ss and does not wrap at an hour', () {
    expect(formatDuration(Duration.zero), '0:00');
    expect(formatDuration(const Duration(seconds: 5)), '0:05');
    expect(formatDuration(const Duration(minutes: 3, seconds: 42)), '3:42');
    expect(formatDuration(const Duration(minutes: 75, seconds: 3)), '75:03');
  });

  test('titleCase capitalises the first letter only', () {
    expect(titleCase('english'), 'English');
    expect(titleCase('Hausa'), 'Hausa');
    expect(titleCase(''), '');
    expect(titleCase('mixed language'), 'Mixed language');
  });
}
