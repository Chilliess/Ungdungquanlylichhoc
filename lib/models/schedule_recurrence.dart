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

  static Iterable<DateTime> between(
      Map<String, dynamic> row, DateTime from, DateTime to) sync* {
    for (var day = DateTime(from.year, from.month, from.day);
        !day.isAfter(to);
        day = DateTime(day.year, day.month, day.day + 1)) {
      if (occursOn(row, day)) yield day;
    }
  }
}
