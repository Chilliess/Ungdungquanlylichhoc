import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/screen/lesson_event_tile.dart';

void main() {
  final event = CalendarEventData<Map<String, dynamic>>(
    title: 'Cấu trúc dữ liệu và giải thuật',
    date: DateTime(2026, 11, 3),
    startTime: DateTime(2026, 11, 3, 6, 45),
    endTime: DateTime(2026, 11, 3, 9, 30),
    color: Colors.red,
    event: const {
      'room': 'A6 - 101',
      'category': 'Thực hành',
      'notes': 'Mang máy tính và chuẩn bị bài tập trước khi đến lớp.',
      'lecturer': 'Chưa có GV'
    },
  );
  testWidgets(
      'groups the title, label, time and location without obsolete teacher text',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
          width: 500, height: 165, child: LessonEventTile(event: event)),
    ))));
    expect(find.text(event.title), findsOneWidget);
    expect(find.text('06:45 – 09:30'), findsOneWidget);
    expect(find.text('A6 - 101'), findsOneWidget);
    expect(find.text('Thực hành'), findsOneWidget);
    expect(find.textContaining('Giảng viên'), findsNothing);
    final title = tester.getRect(find.text(event.title));
    final time = tester.getRect(find.text('06:45 – 09:30'));
    expect(time.top - title.bottom, lessThan(10));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'short and narrow events adapt without layout overflow at large text sizes',
      (tester) async {
    for (final size in [
      const Size(90, 15),
      const Size(140, 30),
      const Size(220, 60),
      const Size(300, 165)
    ]) {
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: Scaffold(
            body: Center(
                child: SizedBox(
                    width: size.width,
                    height: size.height,
                    child: LessonEventTile(event: event)))),
      )));
      expect(find.text(event.title), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
