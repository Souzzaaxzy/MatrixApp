/// Formats a [DateTime] as a short relative time string (Portuguese).
String relativeTime(DateTime dateTime, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(dateTime);

  if (diff.inSeconds < 60) return 'agora';
  if (diff.inMinutes < 60) return 'há ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'há ${diff.inHours} h';
  if (diff.inDays < 7) return 'há ${diff.inDays} d';
  return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}';
}

/// Null-safe variant for optional timestamps (e.g. comment placeholders).
String relativeTimeString(DateTime? dateTime, {DateTime? now}) {
  if (dateTime == null) return '';
  return relativeTime(dateTime, now: now);
}
