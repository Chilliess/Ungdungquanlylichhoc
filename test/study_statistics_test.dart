import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/models/study_statistics.dart';
import 'package:untitled/screen/statistical.dart';

final rows = <Map<String, dynamic>>[
  {
    'id': 's',
    'subject_id': 'm',
    'subjects': {'subject_name': 'Cấu trúc dữ liệu'},
    'start_date': '2026-11-03',
    'end_date': null,
    'recurrence': 'weekly',
    'day_of_week': [3],
    'start_time': '06:45:00',
    'end_time': '09:30:00'
  }
];
void main() {
  test('weekly and monthly totals count actual occurrences and elapsed minutes',
      () {
    final week =
        StudyStatistics(rows, DateTime(2026, 11, 2), DateTime(2026, 11, 8));
    expect(week.sessions, 1);
    expect(week.minutes, 165);
    expect(week.dailyMinutes[DateTime(2026, 11, 3)], 165);
    expect(week.dailyMinutes[DateTime(2026, 11, 4)], 0);
    final month =
        StudyStatistics(rows, DateTime(2026, 11), DateTime(2026, 11, 30));
    expect(month.sessions, 4);
    expect(month.minutes, 660);
    expect(month.subjects.length, 1);
    expect(StudyStatistics.durationMinutes('10:00', '09:00'), 0);
  });
  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets('statistics switches periods without overflow at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          home: StatisticalScreen(
              initialDate: DateTime(2026, 11, 2),
              loadSchedules: () async => rows)));
      await tester.pumpAndSettle();
      expect(find.text('2g 45p'), findsWidgets);
      expect(find.text('Tính theo lịch đã đặt.'), findsNothing);
      await tester.tap(find.text('Tháng'));
      await tester.pumpAndSettle();
      expect(find.text('11g'), findsWidgets);
      await tester.tap(find.byTooltip('Khoảng trước'));
      await tester.pumpAndSettle();
      expect(find.text('0 phút'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
