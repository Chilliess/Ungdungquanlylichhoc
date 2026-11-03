import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/services/home_service.dart';

/// Ngày tham chiếu: 22/10/2026 là thứ Năm -> appWeekday = 5.
final DateTime reference = DateTime(2026, 10, 22, 8, 0);

Map<String, dynamic> subject(String id, String name, String code) => {
      'id': id,
      'subject_name': name,
      'subject_code': code,
      'color_code': '#4A90E2',
    };

Map<String, dynamic> schedule(
  String id, {
  Object? days = const [2],
  String start = '07:00',
  String end = '08:00',
  String subjectName = 'Toán học',
}) =>
    {
      'id': id,
      'subject_id': 's1',
      'day_of_week': days,
      'start_time': start,
      'end_time': end,
      'room': 'A101',
      'lecturer': 'Thầy Nam',
      'periods_count': 2,
      'subjects': subject('s1', subjectName, 'MATH101'),
    };

void main() {
  group('HomeService.buildSnapshot', () {
    test('Snapshot rỗng khi không có dữ liệu', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: const [],
        schedules: const [],
        exams: const [],
        reminders: const [],
        now: reference,
      );

      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.username, isNull);
      expect(snapshot.weeklyLessonCount, 0);
      expect(snapshot.enabledReminderCount, 0);
    });

    test('Một lịch học 3 ngày tạo ra 3 buổi trong tuần', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: [subject('s1', 'Toán học', 'MATH101')],
        schedules: [
          schedule('sch1', days: [2, 4, 6], start: '07:00:00', end: '08:30:00')
        ],
        exams: const [],
        reminders: const [],
        now: reference,
      );

      expect(snapshot.weeklyLessonCount, 3);
      expect(snapshot.weeklyLessons.map((l) => l.appWeekday), [2, 4, 6]);
      expect(snapshot.weeklyLessons.first.subjectName, 'Toán học');
      expect(snapshot.weeklyLessons.first.subjectCode, 'MATH101');
      expect(snapshot.weeklyLessons.first.startTime, '07:00');
      expect(snapshot.weeklyLessons.first.endTime, '08:30');
      expect(snapshot.weeklyLessons.first.room, 'A101');
      expect(snapshot.weeklyLessons.first.lecturer, 'Thầy Nam');
      expect(snapshot.weeklyLessons.first.periodsCount, 2);
      expect(snapshot.weeklyLessons.first.isExam, isFalse);
    });

    test('Buổi học hôm nay được tách riêng theo thứ trong tuần', () {
      // 22/10/2026 là thứ Năm -> appWeekday = 5.
      final snapshot = HomeService.buildSnapshot(
        subjects: [subject('s1', 'Lập trình', 'CS101')],
        schedules: [
          schedule('sch1', days: [4], start: '08:00', end: '09:30'),
          schedule('sch2', days: [5], start: '13:00', end: '14:30'),
        ],
        exams: const [],
        reminders: const [],
        now: reference,
      );

      expect(snapshot.todayLessons.length, 1);
      expect(snapshot.todayLessons.first.id, 'sch2-5');
      expect(snapshot.todayLessons.first.startTime, '13:00');
    });

    test('Buổi học được sắp xếp theo thứ rồi theo giờ bắt đầu', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: const [],
        schedules: [
          schedule('b', days: [2], start: '09:00'),
          schedule('a', days: [2], start: '07:00'),
          schedule('c', days: [3], start: '07:00'),
        ],
        exams: const [],
        reminders: const [],
        now: reference,
      );

      expect(
        snapshot.weeklyLessons.map((l) => l.id).toList(),
        ['a-2', 'b-2', 'c-3'],
      );
    });

    test('Tổng hợp môn học kèm số buổi học trong tuần', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: [subject('s1', 'Toán học', 'MATH101')],
        schedules: [
          schedule('sch1', days: [2, 4])
        ],
        exams: const [],
        reminders: const [],
        now: reference,
      );

      expect(snapshot.subjects.length, 1);
      expect(snapshot.subjects.first.subjectName, 'Toán học');
      expect(snapshot.subjects.first.subjectCode, 'MATH101');
      expect(snapshot.subjects.first.weeklyLessonCount, 2);
      expect(snapshot.subjects.first.color, const Color(0xFF4A90E2));
    });

    test('Kỳ thi được đưa vào upcomingExams và sắp xếp theo ngày', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: const [],
        schedules: const [],
        exams: [
          {
            'id': 'e2',
            'exam_date': '2026-12-01',
            'start_time': '08:00',
            'room': 'B202',
            'subjects': subject('s2', 'Vật lý', 'PHY201'),
          },
          {
            'id': 'e1',
            'exam_date': '2026-11-01',
            'start_time': '09:00',
            'subjects': subject('s2', 'Vật lý', 'PHY201'),
          },
        ],
        reminders: const [],
        now: reference,
      );

      expect(snapshot.upcomingExams.length, 2);
      expect(snapshot.upcomingExams.first.id, 'e1');
      expect(snapshot.upcomingExams.first.isExam, isTrue);
      expect(snapshot.upcomingExams.first.subjectName, 'Vật lý');
      // Không phải hôm nay nên không nằm trong todayLessons.
      expect(snapshot.todayLessons, isEmpty);
    });

    test('Kỳ thi diễn ra hôm nay được thêm vào buổi học hôm nay', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: const [],
        schedules: const [],
        exams: [
          {
            'id': 'e1',
            'exam_date': '2026-10-22',
            'start_time': '08:00',
            'subjects': subject('s2', 'Vật lý', 'PHY201'),
          }
        ],
        reminders: const [],
        now: reference,
      );

      expect(snapshot.todayLessons.length, 1);
      expect(snapshot.todayLessons.first.id, 'e1');
      expect(snapshot.todayLessons.first.isExam, isTrue);
    });

    test('Nhắc nhở được liên kết với lịch học và đếm số nhắc nhở đang bật', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: const [],
        schedules: [schedule('sch1')],
        exams: const [],
        reminders: [
          {
            'id': 'r1',
            'schedule_id': 'sch1',
            'schedule_type': 'schedule',
            'remind_before_minutes': 30,
            'is_enabled': true,
          },
          {
            'id': 'r2',
            'schedule_id': 'sch1',
            'schedule_type': 'schedule',
            'remind_before_minutes': 10,
            'is_enabled': false,
          },
        ],
        now: reference,
      );

      expect(snapshot.reminders.length, 2);
      expect(snapshot.enabledReminderCount, 1);
      expect(snapshot.reminders.first.subjectName, 'Toán học');
      expect(snapshot.reminders.first.startTime, '07:00');
      expect(snapshot.reminders.first.remindBeforeMinutes, 30);
      expect(snapshot.reminders.first.isEnabled, isTrue);
      expect(snapshot.reminders.last.isEnabled, isFalse);
    });

    test('Nhắc nhở cho kỳ thi lấy ngày thi và giờ bắt đầu', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: const [],
        schedules: const [],
        exams: [
          {
            'id': 'e1',
            'exam_date': '2026-11-01',
            'start_time': '09:00',
            'subjects': subject('s2', 'Vật lý', 'PHY201'),
          }
        ],
        reminders: [
          {
            'id': 'r1',
            'schedule_id': 'e1',
            'schedule_type': 'exam',
            'remind_before_minutes': 60,
            'is_enabled': true,
          }
        ],
        now: reference,
      );

      final reminder = snapshot.reminders.single;
      expect(reminder.isExam, isTrue);
      expect(reminder.subjectName, 'Vật lý');
      expect(reminder.startTime, '09:00');
      expect(reminder.examDate, DateTime(2026, 11, 1));
    });

    test('Lịch học thiếu day_of_week bị bỏ qua', () {
      final snapshot = HomeService.buildSnapshot(
        subjects: const [],
        schedules: [
          {
            'id': 'sch1',
            'start_time': '07:00',
            'end_time': '08:00',
            'subjects': subject('s1', 'Toán học', 'MATH101'),
          }
        ],
        exams: const [],
        reminders: const [],
        now: reference,
      );

      expect(snapshot.weeklyLessonCount, 0);
      expect(snapshot.todayLessons, isEmpty);
    });
  });
  test(
      'one-day lessons do not repeat into later weeks and upcoming dates are accurate',
      () {
    final once = schedule('once', days: [5])
      ..addAll({'start_date': '2026-10-22', 'end_date': '2026-10-22'});
    final later = schedule('later', days: [6], subjectName: 'Học ngày mai')
      ..addAll({'start_date': '2026-10-23', 'end_date': '2026-10-23'});
    final data = HomeService.buildSnapshot(
        subjects: [],
        schedules: [once, later],
        exams: [],
        reminders: [],
        now: reference);
    expect(data.todayLessons.length, 1);
    expect(data.upcomingLessons.length, 1);
    expect(data.upcomingLessons.single.date, DateTime(2026, 10, 23));
    final nextWeek = HomeService.buildSnapshot(
        subjects: [],
        schedules: [once, later],
        exams: [],
        reminders: [],
        now: DateTime(2026, 10, 29));
    expect(nextWeek.todayLessons, isEmpty);
    expect(nextWeek.upcomingLessons, isEmpty);
  });
  test('upcoming lessons include a course starting more than two months later',
      () {
    final futureDate = DateTime(2027, 2, 1);
    final future = schedule('future', days: [futureDate.weekday + 1])
      ..addAll({'start_date': '2027-02-01', 'end_date': '2027-02-01'});
    final snapshot = HomeService.buildSnapshot(
        subjects: [],
        schedules: [future],
        exams: [],
        reminders: [],
        now: reference);
    expect(snapshot.upcomingLessons.single.date, futureDate);
  });
}
