import 'home_models.dart';
import 'schedule_recurrence.dart';
import '../services/notification_reads.dart';

/// A dated occurrence, derived from the same calendar rules as the home page.
class StudyNotification {
  const StudyNotification(
      this.lesson, this.start, this.end, this.remindAt, this.key);
  final String key;
  final TodayLesson lesson;
  final DateTime start, end;
  final DateTime? remindAt;

  bool isDue(DateTime now) =>
      remindAt != null && !now.isBefore(remindAt!) && now.isBefore(end);

  static List<StudyNotification> fromSnapshot(HomeSnapshot data, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final through = DateTime(now.year, now.month, now.day + 7);
    final result = <StudyNotification>[];
    final seen = <String>{};
    void add(TodayLesson lesson, DateTime date, String id) {
      final startTime = WeekdayUtils.parseTime(lesson.startTime);
      final endTime = WeekdayUtils.parseTime(lesson.endTime);
      if (startTime == null || endTime == null) return;
      final start = DateTime(
          date.year, date.month, date.day, startTime.hour, startTime.minute);
      final end = DateTime(
          date.year, date.month, date.day, endTime.hour, endTime.minute);
      if (!end.isAfter(now) ||
          !start.isBefore(through) ||
          !seen.add('${lesson.isExam}:$id:$start')) {
        return;
      }
      final reminders = data.reminders.where((r) =>
          r.isEnabled && r.isExam == lesson.isExam && r.scheduleId == id);
      final minutes = reminders.isEmpty
          ? null
          : reminders
              .map((r) => r.remindBeforeMinutes)
              .reduce((a, b) => a > b ? a : b);
      result.add(StudyNotification(
          lesson,
          start,
          end,
          minutes == null ? null : start.subtract(Duration(minutes: minutes)),
          NotificationReads.key(
              lesson.isExam ? 'exam' : 'schedule', id, start)));
    }

    for (final lesson in data.weeklyLessons) {
      final row = lesson.schedule;
      if (row == null) continue;
      for (var offset = 0; offset < 7; offset++) {
        final date = DateTime(today.year, today.month, today.day + offset);
        if (ScheduleRecurrence.occursOn(row, date)) {
          add(lesson, date, row['id']?.toString() ?? lesson.id);
        }
      }
    }
    for (final exam in data.upcomingExams) {
      if (exam.date != null) add(exam, exam.date!, exam.id);
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }
}
