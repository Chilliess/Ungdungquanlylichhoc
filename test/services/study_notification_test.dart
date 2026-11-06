import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/models/study_notification.dart';
import 'package:untitled/services/home_service.dart';

void main() {
  test('due reminders respect lead time, enabled state and event end', () {
    final now = DateTime(2026, 11, 5, 8, 50);
    final data = HomeService.buildSnapshot(subjects: [], schedules: [
      {
        'id': 'one',
        'start_date': '2026-11-05',
        'end_date': '2026-11-05',
        'start_time': '09:00',
        'end_time': '10:00',
        'day_of_week': [5],
        'subjects': {'subject_name': 'Toán'}
      },
    ], exams: [], reminders: [
      {
        'schedule_id': 'one',
        'schedule_type': 'schedule',
        'is_enabled': true,
        'remind_before_minutes': 15
      },
    ], now: now);
    final item = StudyNotification.fromSnapshot(data, now).single;
    expect(item.isDue(now), isTrue);
    expect(item.isDue(DateTime(2026, 11, 5, 8, 44)), isFalse);
    expect(item.isDue(DateTime(2026, 11, 5, 10)), isFalse);
    expect(StudyNotification.fromSnapshot(data, DateTime(2026, 11, 5, 10)),
        isEmpty);
  });

  test(
      'recurrences and exams use exact dates, deduplicate, exclude disabled reminders',
      () {
    final now = DateTime(2026, 11, 5, 8, 50);
    final data = HomeService.buildSnapshot(subjects: [], schedules: [
      {
        'id': 'daily',
        'recurrence': 'daily',
        'day_of_week': [2, 3, 4],
        'start_date': '2026-11-05',
        'end_date': '2026-11-07',
        'start_time': '09:00',
        'end_time': '10:00'
      },
    ], exams: [
      {
        'id': 'exam',
        'exam_date': '2026-11-06',
        'start_time': '07:00',
        'end_time': '08:00'
      },
      {
        'id': 'old',
        'exam_date': '2026-11-04',
        'start_time': '07:00',
        'end_time': '08:00'
      },
      {
        'id': 'far',
        'exam_date': '2026-12-04',
        'start_time': '07:00',
        'end_time': '08:00'
      },
    ], reminders: [
      {
        'schedule_id': 'daily',
        'schedule_type': 'schedule',
        'is_enabled': false,
        'remind_before_minutes': 15
      },
      {
        'schedule_id': 'exam',
        'schedule_type': 'exam',
        'is_enabled': true,
        'remind_before_minutes': 30
      },
    ], now: now);
    final items = StudyNotification.fromSnapshot(data, now);
    expect(items.length, 4);
    expect(items.where((i) => !i.lesson.isExam).map((i) => i.start.day),
        [5, 6, 7]);
    expect(items.where((i) => i.isDue(now)), isEmpty);
    final exam = items.singleWhere((i) => i.lesson.isExam);
    expect(exam.isDue(DateTime(2026, 11, 6, 6, 30)), isTrue);
  });
}
