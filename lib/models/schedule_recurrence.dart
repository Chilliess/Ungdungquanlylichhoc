/// Shared occurrence rules for calendar, home, statistics and reminders.
class ScheduleRecurrence {
  static const labels = {
    'none': 'Không lặp',
    'daily': 'Hằng ngày',
    'weekly': 'Hằng tuần',
    'monthly': 'Hằng tháng',
    'yearly': 'Hằng năm'
  };
  static DateTime? date(dynamic value) =>
      DateTime.tryParse(value?.toString() ?? '');
  static String frequency(Map<String, dynamic> row) =>
      row['recurrence']?.toString() ??
      (row['start_date'] != null && row['start_date'] == row['end_date']
          ? 'none'
          : 'weekly');
  static bool occursOn(Map<String, dynamic> row, DateTime value) {
    final day = DateTime(value.year, value.month, value.day);
    final start = date(row['start_date']);
    final end = date(row['end_date']);
    if (start != null && day.isBefore(start) ||
        end != null && day.isAfter(end)) {
      return false;
    }
    switch (frequency(row)) {
      case 'none':
        return start != null && day == start;
      case 'daily':
        return true;
      case 'monthly':
        return start != null && day.day == start.day;
      case 'yearly':
        return start != null &&
            day.month == start.month &&
            day.day == start.day;
      default:
        final raw = row['day_of_week'];
        final days = raw is List ? raw : [raw];
        return days.any((d) => int.tryParse('$d') == day.weekday + 1);
    }
  }

  /// Find the next actual occurrence without scanning every intervening day.
  static DateTime? nextOccurrence(Map<String, dynamic> row, DateTime from,
      {required DateTime through}) {
    var first = DateTime(from.year, from.month, from.day);
    final start = date(row['start_date']);
    final end = date(row['end_date']);
    final limit = end != null && end.isBefore(through) ? end : through;
    if (start != null && first.isBefore(start)) {
      first = DateTime(start.year, start.month, start.day);
      if (first.isBefore(start)) {
        first = DateTime(start.year, start.month, start.day + 1);
      }
    }
    if (first.isAfter(limit)) return null;
    bool eligible(DateTime value) =>
        !value.isBefore(first) && !value.isAfter(limit) && occursOn(row, value);
    switch (frequency(row)) {
      case 'none':
        return start != null && eligible(start) ? start : null;
      case 'daily':
        return eligible(first) ? first : null;
      case 'monthly':
        if (start == null) return null;
        var month = DateTime(first.year, first.month);
        while (!month.isAfter(limit)) {
          final candidate = DateTime(month.year, month.month, start.day);
          // DateTime rolls nonexistent dates into the following month.
          if (candidate.month == month.month && eligible(candidate)) {
            return candidate;
          }
          month = DateTime(month.year, month.month + 1);
        }
        return null;
      case 'yearly':
        if (start == null) return null;
        for (var year = first.year; year <= limit.year; year++) {
          final candidate = DateTime(year, start.month, start.day);
          if (candidate.month == start.month &&
              candidate.day == start.day &&
              eligible(candidate)) {
            return candidate;
          }
        }
        return null;
      default:
        for (var offset = 0; offset < 7; offset++) {
          final candidate =
              DateTime(first.year, first.month, first.day + offset);
          if (candidate.isAfter(limit)) break;
          if (eligible(candidate)) return candidate;
        }
        return null;
    }
  }

  static Iterable<DateTime> between(
      Map<String, dynamic> row, DateTime from, DateTime to) sync* {
    for (var day = DateTime(from.year, from.month, from.day);
        !day.isAfter(to);
        day = DateTime(day.year, day.month, day.day + 1)) {
      if (occursOn(row, day)) yield day;
    }
  }
}
