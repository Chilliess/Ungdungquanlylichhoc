import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/screen/view_schedule_screen.dart';
import 'package:untitled/screen/lesson_editor.dart';
import 'package:untitled/screen/lesson_categories.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1200, 900)
  ]) {
    testWidgets('agenda and existing date navigation fit $size',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(MaterialApp(
          home: ViewScheduleScreen(initialDate: DateTime(2026, 11, 4))));
      await tester.pumpAndSettle();
      expect(find.byType(DayView<Map<String, dynamic>>), findsNothing);
      expect(find.byKey(const ValueKey('schedule-agenda')), findsOneWidget);
      expect(find.text('Ngày này chưa có lịch trình'), findsOneWidget);
      expect(
          find.text('Từ ngày 02/11/2026 đến ngày 08/11/2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Ngày sau'));
      await tester.pumpAndSettle();
      expect(find.text('Ngày 05/11/2026'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schedule-browse')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-month')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schedule-browse')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-year')), findsOneWidget);
      await tester.tap(find.byTooltip('Năm sau'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule-month-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule-date-2027-2-15')));
      await tester.pumpAndSettle();
      expect(find.text('Ngày 15/02/2027'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schedule-today')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('search finds a category and opens the correct event for editing',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(const MaterialApp(home: ViewScheduleScreen()));
    await tester.pumpAndSettle();
    final calendar =
        tester.widget<CalendarControllerProvider<Map<String, dynamic>>>(
            find.byType(CalendarControllerProvider<Map<String, dynamic>>));
    final date = DateTime(2026, 12, 15);
    calendar.controller.add(CalendarEventData<Map<String, dynamic>>(
      title: 'Lập trình di động',
      date: date,
      startTime: DateTime(2026, 12, 15, 13),
      endTime: DateTime(2026, 12, 15, 15),
      event: const {
        'id': 'lesson-123',
        'is_exam': false,
        'room': 'A203',
        'notes': 'Mang laptop',
        'category': 'Thực hành',
        'start_date': '2026-12-15',
        'end_date': '2026-12-15',
        'start_time': '13:00',
        'end_time': '15:00',
        'subjects': {
          'subject_name': 'Lập trình di động',
          'subject_code': 'MOB101'
        },
      },
    ));
    await tester.tap(find.byKey(const ValueKey('schedule-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'không có môn này');
    await tester.pumpAndSettle();
    expect(find.text('Không tìm thấy môn học phù hợp'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'thực hành');
    await tester.pumpAndSettle();
    expect(find.text('Lập trình di động'), findsOneWidget);
    await tester.tap(find.text('Lập trình di động'));
    await tester.pumpAndSettle();
    expect(find.text('Ngày 15/12/2026'), findsOneWidget);
    final tile = find.text('Lập trình di động').first;
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Mang laptop')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Thực hành')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('lesson-detail-category')), findsOneWidget);
    expect(find.text('Nhãn: '), findsNothing);
    expect(find.text('Giảng viên: '), findsNothing);
    final badge =
        tester.getRect(find.byKey(const ValueKey('lesson-detail-category')));
    final title = tester.getRect(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Lập trình di động')));
    expect(badge.left, greaterThanOrEqualTo(title.right));
    expect(badge.center.dy, closeTo(title.center.dy, 1));
    await tester.tap(find.byKey(const ValueKey('lesson-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(LessonEditor), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('lesson-title')))
            .controller!
            .text,
        'Lập trình di động');
    expect(
        tester
            .widget<LessonCategoryField>(
                find.byKey(const ValueKey('lesson-category')))
            .value,
        'Thực hành');
    final save = find.byKey(const ValueKey('lesson-save'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-action')));
    await tester.pumpAndSettle();
    expect(find.text('Vui lòng đăng nhập để lưu lịch học.'), findsOneWidget);
    expect(find.byType(LessonEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add button opens a blank editor on a small mobile screen',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(const MaterialApp(home: ViewScheduleScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-add')));
    await tester.pumpAndSettle();
    expect(find.text('Lịch thi'), findsOneWidget);
    expect(find.text('Nhập ảnh / PDF'), findsOneWidget);
    await tester.tap(find.text('Lịch học'));
    await tester.pumpAndSettle();
    expect(find.byType(LessonEditor), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('lesson-title')))
            .controller!
            .text,
        isEmpty);
    expect(find.text('Chọn giờ'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
