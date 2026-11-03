import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/models/schedule_recurrence.dart';
import 'package:untitled/services/home_service.dart';

void main() {
  Map<String, dynamic> row(String frequency, String start, [String? end]) => {
        'id': 'schedule',
        'subject_id': 'subject',
        'recurrence': frequency,
        'start_date': start,
        'end_date': end,
        'day_of_week': [3],
        'start_time': '07:00',
        'end_time': '09:00',
        'subjects': {'subject_name': 'Toán'},
      };
  test('daily and non-repeating rules respect inclusive bounds', () {
    final daily = row('daily', '2026-11-02', '2026-11-04');
    expect(
        ScheduleRecurrence.between(
                daily, DateTime(2026, 11, 1), DateTime(2026, 11, 6))
            .length,
        3);
    final once = row('none', '2026-11-02');
    expect(
        ScheduleRecurrence.between(
                once, DateTime(2026, 11, 1), DateTime(2026, 11, 30))
            .length,
        1);
  });
  test('legacy weekly multi-day schedules retain their weekdays', () {
    final legacy = {
      ...row('weekly', '2026-11-02', '2026-11-08'),
      'day_of_week': [2, 4],
      'recurrence': null
    };
    expect(
        ScheduleRecurrence.between(
                legacy, DateTime(2026, 11, 1), DateTime(2026, 11, 30))
            .map((d) => d.day),
        [2, 4]);
  });
  test('monthly and yearly skip invalid dates instead of drifting', () {
    final monthly = row('monthly', '2026-01-31');
    expect(
        ScheduleRecurrence.between(
                monthly, DateTime(2026, 1, 1), DateTime(2026, 4, 30))
            .toList(),
        [DateTime(2026, 1, 31), DateTime(2026, 3, 31)]);
    final leap = row('yearly', '2024-02-29');
    expect(
        ScheduleRecurrence.between(leap, DateTime(2025), DateTime(2028, 3))
            .toList(),
        [DateTime(2028, 2, 29)]);
  });
  test('home finds monthly and yearly lessons beyond the following week', () {
    final snapshot = HomeService.buildSnapshot(
        subjects: [],
        schedules: [row('monthly', '2026-01-31'), row('yearly', '2024-02-29')],
        exams: [],
        reminders: [],
        now: DateTime(2026, 2, 1));
    expect(snapshot.todayLessons, isEmpty);
    expect(snapshot.upcomingLessons.map((l) => l.date),
        [DateTime(2026, 3, 31), DateTime(2028, 2, 29)]);
  });
  test('home daily recurrence appears once on every eligible day', () {
    final snapshot = HomeService.buildSnapshot(
        subjects: [],
        schedules: [row('daily', '2026-11-02')],
        exams: [],
        reminders: [],
        now: DateTime(2026, 11, 4));
    expect(snapshot.todayLessons.length, 1);
    expect(snapshot.upcomingLessons.single.date, DateTime(2026, 11, 5));
  });
}
