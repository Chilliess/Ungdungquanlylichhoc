import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/services/study_data.dart';
import 'package:untitled/services/home_service.dart';

void main() {
  test('profile name wins; registration name survives a missing profile', () {
    expect(
        accountDisplayName(
            profileName: '  Minh Anh ',
            metadata: {'username': 'Tên đăng ký'},
            email: 'anh@example.com'),
        'Minh Anh');
    expect(accountDisplayName(metadata: {'username': 'Tên đăng ký'}),
        'Tên đăng ký');
    expect(accountDisplayName(metadata: {'full_name': 'Google Name'}),
        'Google Name');
    expect(accountDisplayName(profileName: ' ', email: 'minhanh@example.com'),
        'minhanh');
    expect(accountDisplayName(), isNull);
  });

  test('owned schedules resolve against owned subjects and reject foreign rows',
      () {
    final rows = attachOwnedSubjects([
      {'id': 'one', 'subject_id': 'subject', 'user_id': 'a'},
      {'id': 'bad-parent', 'subject_id': 'other-subject', 'user_id': 'a'},
      {'id': 'foreign', 'subject_id': 'subject', 'user_id': 'b'},
    ], [
      {'id': 'subject', 'user_id': 'a', 'subject_name': 'Tên mới'},
      {'id': 'other-subject', 'user_id': 'b', 'subject_name': 'Tên riêng tư'},
    ], 'a');
    expect(rows.length, 2);
    expect(rows.first['subjects']['subject_name'], 'Tên mới');
    expect(rows.last['subjects'], isNull);
    expect(rows.toString(), isNot(contains('Tên riêng tư')));
  });

  test(
      'weekly summary counts actual daily/one-time occurrences in the current week',
      () {
    final snapshot = HomeService.buildSnapshot(subjects: [
      {'id': 's', 'subject_name': 'Toán'},
    ], schedules: [
      {
        'id': 'daily',
        'subject_id': 's',
        'recurrence': 'daily',
        'start_date': '2026-11-02',
        'end_date': '2026-11-04',
        'start_time': '07:00',
        'end_time': '08:00'
      },
      {
        'id': 'past',
        'subject_id': 's',
        'recurrence': 'none',
        'start_date': '2026-10-31',
        'end_date': '2026-10-31'
      },
    ], exams: [], reminders: [], now: DateTime(2026, 11, 4));
    expect(snapshot.weeklyLessonCount, 3);
    expect(snapshot.subjects.single.weeklyLessonCount, 3);
    expect(snapshot.todayLessons.length, 1);
  });
}
