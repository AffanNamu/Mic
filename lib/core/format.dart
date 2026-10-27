/// "just now", "5 minutes ago", "2 hours ago", "yesterday", "3 days ago", or
/// the date for anything older than a week.
String formatAgo(DateTime then, DateTime now) {
  final diff = now.difference(then);
  if (diff.isNegative || diff < const Duration(minutes: 1)) return 'just now';
  if (diff < const Duration(hours: 1)) {
    final m = diff.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (diff < const Duration(days: 1)) {
    final h = diff.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  final days = diff.inDays;
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days days ago';
  final l = then.toLocal();
  return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
      '${l.day.toString().padLeft(2, '0')}';
}

/// `m:ss`, e.g. 3:42.
String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

/// "english" → "English". Wire values come back lower-case.
String titleCase(String text) =>
    text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
