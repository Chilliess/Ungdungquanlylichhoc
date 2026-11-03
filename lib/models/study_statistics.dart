import 'schedule_recurrence.dart';

class SubjectStatistic {
  SubjectStatistic(this.name);
  final String name;
  int sessions = 0, minutes = 0;
}

class StudyStatistics {
  StudyStatistics(
      List<Map<String, dynamic>> rows, DateTime start, DateTime end) {
    for (var day = start;
        !day.isAfter(end);
        day = DateTime(day.year, day.month, day.day + 1)) {
      dailyMinutes[day] = 0;
      dailySessions[day] = 0;
    }
    for (final row in rows) {
      final dates = ScheduleRecurrence.between(row, start, end).toList();
      if (dates.isEmpty) continue;
      final subject = row['subjects'] is Map ? row['subjects'] as Map : {};
      final id = (row['subject_id'] ?? row['id']).toString();
      final stat = subjects.putIfAbsent(
          id,
          () => SubjectStatistic(
              subject['subject_name']?.toString() ?? 'Môn học'));
      final duration = durationMinutes(row['start_time'], row['end_time']);
      for (final day in dates) {
        sessions++;
        minutes += duration;
        stat.sessions++;
        stat.minutes += duration;
        dailyMinutes[day] = (dailyMinutes[day] ?? 0) + duration;
        dailySessions[day] = (dailySessions[day] ?? 0) + 1;
      }
    }
  }
  int sessions = 0, minutes = 0;
  final subjects = <String, SubjectStatistic>{};
  final dailyMinutes = <DateTime, int>{}, dailySessions = <DateTime, int>{};
  static int durationMinutes(dynamic start, dynamic end) {
    int? parse(dynamic value) {
      final parts = value?.toString().split(':') ?? [];
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return null;
      }
      return h * 60 + m;
    }

    final a = parse(start), b = parse(end);
    return a == null || b == null || b <= a ? 0 : b - a;
  }

  static String duration(int minutes) => minutes < 60
      ? '$minutes phút'
      : '${minutes ~/ 60}g${minutes % 60 == 0 ? '' : ' ${minutes % 60}p'}';
}
