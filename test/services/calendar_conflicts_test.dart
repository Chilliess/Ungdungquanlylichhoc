import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/services/calendar_conflicts.dart';

Map<String, dynamic> row(String id, String day, String start, String end) => {
      'id': id,
      'start_date': day,
      'end_date': day,
      'recurrence': 'none',
      'start_time': start,
      'end_time': end,
    };
void main() {
  test('overlaps both kinds, touching endpoints and other dates are allowed',
      () {
    final draft = row('new', '2026-11-06', '09:00', '10:00');
    final schedules = [
      row('overlap', '2026-11-06', '09:30', '11:00'),
      row('touch', '2026-11-06', '10:00', '11:00'),
      row('old', '2026-11-05', '09:00', '10:00'),
    ];
    final exams = [
      {
        'id': 'exam',
        'exam_date': '2026-11-06',
        'start_time': '08:30',
        'end_time': '09:30'
      }
    ];
    expect(calendarConflicts(draft, schedules, exams).length, 2);
    expect(
        calendarConflicts(draft, schedules, exams, excludeId: 'overlap').length,
        1);
  });
  test(
      'repeat conflict beyond first occurrence and excluded IDs are type scoped',
      () {
    final draft = {
      ...row('new', '2026-11-06', '09:00', '10:00'),
      'recurrence': 'weekly',
      'day_of_week': [6],
      'end_date': '2026-12-06'
    };
    final future = row('same', '2026-11-20', '09:30', '10:30');
    final exams = [
      {
        'id': 'same',
        'exam_date': '2026-11-27',
        'start_time': '09:15',
        'end_time': '10:00'
      }
    ];
    expect(calendarConflicts(draft, [future], exams).length, 2);
    expect(calendarConflicts(draft, [future], exams, excludeId: 'same').single,
        startsWith('Thi:'));
    final monthly = {...draft, 'recurrence': 'monthly'};
    expect(calendarConflicts(monthly, [future], exams), isEmpty);
  });
}
