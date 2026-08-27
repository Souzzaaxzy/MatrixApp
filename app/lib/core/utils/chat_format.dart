/// Chat time/date formatting helpers.
///
/// Timezone strategy: the SERVER stores the authoritative timestamp
/// (UTC ISO-8601) and the CLIENT renders it in the device's local time
/// zone. We never trust a clock sent by the client as the source of truth.
library;

/// Formats a timestamp as a 24h local time (`HH:mm`) — used on each message
/// and as the last-message time in the conversations list.
String chatClock(DateTime dt, {DateTime? now}) {
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Formats the conversations-list time: today → `HH:mm`; yesterday →
/// `Ontem`; this week → weekday (`seg`..`dom`); otherwise `dd/mm`/`dd/mm/yy`.
String chatListTime(DateTime dt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = dt.toLocal();

  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(day).inDays;

  if (diffDays <= 0) return chatClock(local);
  if (diffDays == 1) return 'Ontem';
  if (diffDays < 7) {
    const weekdays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
    final wd = local.weekday - 1; // DateTime.weekday: 1=Mon..7=Sun
    return weekdays[wd];
  }
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  if (local.year != reference.year) return '$dd/$mm/${local.year % 100}';
  return '$dd/$mm';
}

const _weekdayLong = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
const _monthLong = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// A human-friendly day label for in-conversation separators:
/// any date, "Hoje" or "Ontem".
String chatDayLabel(DateTime dt, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final local = dt.toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(local.year, local.month, local.day);
  final diffDays = today.difference(day).inDays;
  if (diffDays == 0) return 'Hoje';
  if (diffDays == 1) return 'Ontem';
  final wd = _weekdayLong[local.weekday - 1];
  if (local.year == reference.year) return '$wd, ${local.day} de ${_monthLong[local.month - 1]}';
  return '${local.day} de ${_monthLong[local.month - 1]} de ${local.year}';
}