import 'package:calendar_view/calendar_view.dart';
import 'package:flutter/gestures.dart';
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

  Future<void> pumpSchedule(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const MaterialApp(home: ViewScheduleScreen()));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(1200, 900),
    const Size(390, 800),
    const Size(320, 640)
  ]) {
    testWidgets('shows only the day calendar at $size', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const MaterialApp(home: ViewScheduleScreen()));
      await tester.pumpAndSettle();

      final day = find.byType(DayView<Map<String, dynamic>>);
      expect(day, findsOneWidget);
      final browseButton =
          tester.getRect(find.byKey(const ValueKey('schedule-browse')));
      final todayButton =
          tester.getRect(find.byKey(const ValueKey('schedule-today')));
      expect(browseButton.width, lessThanOrEqualTo(220));
      expect(browseButton.right, lessThanOrEqualTo(todayButton.left));
      final midnight = find.byKey(const ValueKey('schedule-midnight-label'));
      expect(midnight, findsWidgets);
      expect(tester.getRect(midnight.first).top,
          lessThan(tester.getRect(find.text('01:00').first).top));
      final hour = find.text('01:00').first;
      final header =
          tester.getRect(find.byKey(const ValueKey('schedule-range-header')));
      final strip =
          tester.getRect(find.byKey(const ValueKey('schedule-week-strip')));
      expect(header.left, tester.getRect(day).left);
      expect(strip.left, header.left);
      expect(strip.width, header.width);
      final selectedDate =
          tester.widget<DayView<Map<String, dynamic>>>(day).initialDay!;
      final monday = DateTime(selectedDate.year, selectedDate.month,
          selectedDate.day - selectedDate.weekday + 1);
      for (var index = 0; index < 7; index++) {
        final date = DateTime(monday.year, monday.month, monday.day + index);
        final cell = tester.getRect(find.byKey(ValueKey(
            'schedule-week-day-${date.year}-${date.month}-${date.day}')));
        expect(cell.width, closeTo(strip.width / 7, 0.01));
        expect(cell.center.dx,
            closeTo(strip.left + strip.width * (index + 0.5) / 7, 0.01));
      }
      expect(strip.top, closeTo(header.bottom, 0.01));
      expect(tester.getRect(midnight.first).top,
          greaterThanOrEqualTo(strip.bottom));

      final midnightRect = tester.getRect(midnight.first);
      final hourRect = tester.getRect(hour);
      final calendar = tester.widget<DayView<Map<String, dynamic>>>(day);
      final columnCenter =
          tester.getRect(day).left + calendar.timeLineWidth! / 2;
      expect(midnightRect.center.dx, closeTo(columnCenter, 0.5));
      expect(hourRect.center.dx, closeTo(columnCenter, 0.5));
      expect(midnightRect.width, calendar.timeLineWidth);
      expect(hourRect.width, calendar.timeLineWidth);
      expect(tester.widget<Text>(midnight.first).textAlign, TextAlign.center);
      expect(tester.widget<Text>(hour).textAlign, TextAlign.center);
      expect(tester.widget<Text>(midnight.first).style!.fontSize,
          tester.widget<Text>(hour).style!.fontSize);
      expect(midnightRect.height, closeTo(hourRect.height, 0.01));
      final today = DateTime.now();
      expect(calendar.initialDay!.year, today.year);
      expect(calendar.initialDay!.month, today.month);
      expect(calendar.initialDay!.day, today.day);

      expect(find.byType(MonthView<Map<String, dynamic>>), findsNothing);
      expect(find.byKey(const ValueKey('schedule-calendar-divider')),
          findsNothing);
      expect(tester.takeException(), isNull);

      final state = tester.state<DayViewState<Map<String, dynamic>>>(day);
      final originalDate = state.currentDate;
      await tester.tap(
          find.descendant(of: day, matching: find.byIcon(Icons.chevron_right)));
      await tester.pumpAndSettle();
      expect(state.currentDate, originalDate.add(const Duration(days: 1)));
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 800),
    const Size(1200, 900)
  ]) {
    testWidgets(
        'month and year navigation at $size selects a date and returns home',
        (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const MaterialApp(home: ViewScheduleScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule-browse')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-month')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('schedule-browse')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-year')), findsOneWidget);
      await tester.tap(find.byTooltip('Năm sau'));
      await tester.pumpAndSettle();
      final year = DateTime.now().year + 1;
      await tester.tap(find.byKey(const ValueKey('schedule-month-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('schedule-date-$year-2-15')));
      await tester.pumpAndSettle();
      final day = find.byType(DayView<Map<String, dynamic>>);
      expect(tester.state<DayViewState<Map<String, dynamic>>>(day).currentDate,
          DateTime(year, 2, 15));
      expect(
          find.byKey(const ValueKey('schedule-live-time-label')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('schedule-today')));
      await tester.pumpAndSettle();
      final today = DateTime.now();
      expect(tester.state<DayViewState<Map<String, dynamic>>>(day).currentDate,
          DateTime(today.year, today.month, today.day));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'week strip follows the selected day across month and year boundaries',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpWidget(const MaterialApp(home: ViewScheduleScreen()));
    await tester.pumpAndSettle();
    final day = find.byType(DayView<Map<String, dynamic>>);
    tester
        .state<DayViewState<Map<String, dynamic>>>(day)
        .jumpToDate(DateTime(2026, 12, 31));
    await tester.pumpAndSettle();
    expect(find.text('Từ ngày 28/12/2026 đến ngày 03/01/2027'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('schedule-week-day-2027-1-2')));
    await tester.pumpAndSettle();
    expect(tester.state<DayViewState<Map<String, dynamic>>>(day).currentDate,
        DateTime(2027, 1, 2));
    final selected = find.byKey(const ValueKey('schedule-selected-week-day'));
    expect(find.descendant(of: selected, matching: find.text('2')),
        findsOneWidget);
    final decoration =
        tester.widget<Container>(selected).decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.border, isNotNull);
    tester
        .state<DayViewState<Map<String, dynamic>>>(day)
        .jumpToDate(DateTime(2027, 1, 4));
    await tester.pumpAndSettle();
    expect(find.text('Từ ngày 04/01/2027 đến ngày 10/01/2027'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zooms during navigation and ignores repeated taps until settled',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpSchedule(tester);
    final browse = find.byKey(const ValueKey('schedule-browse'));
    await tester.tap(browse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final opacity = tester
        .widget<Opacity>(
            find.byKey(const ValueKey('schedule-transition-opacity')))
        .opacity;
    final scale = tester
        .widget<Transform>(
            find.byKey(const ValueKey('schedule-transition-scale')))
        .transform
        .entry(0, 0);
    expect(opacity, inExclusiveRange(0, 1));
    expect(scale, inExclusiveRange(0.94, 1));
    await tester.tap(browse);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-month')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-year')), findsNothing);
    expect(
        tester
            .widget<Opacity>(
                find.byKey(const ValueKey('schedule-transition-opacity')))
            .opacity,
        1);
    await tester.tap(browse);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('respects reduced motion when changing calendar views',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: const ViewScheduleScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-browse')));
    await tester.pump();
    expect(find.byKey(const ValueKey('schedule-month')), findsOneWidget);
    expect(
        tester
            .widget<Opacity>(
                find.byKey(const ValueKey('schedule-transition-opacity')))
            .opacity,
        1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search finds a category and opens the correct event for editing',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 800));
    await tester.pumpWidget(const MaterialApp(home: ViewScheduleScreen()));
    await tester.pumpAndSettle();
    final day = find.byType(DayView<Map<String, dynamic>>);
    final calendar = tester.widget<DayView<Map<String, dynamic>>>(day);
    final date = DateTime(2026, 12, 15);
    calendar.controller!.add(CalendarEventData<Map<String, dynamic>>(
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
    expect(tester.state<DayViewState<Map<String, dynamic>>>(day).currentDate,
        date);
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

  testWidgets('schedule time grid scrolls with mouse and touch',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpSchedule(tester);

    final day = find.byType(DayView<Map<String, dynamic>>);
    final verticalScrollable = tester
        .elementList(
            find.descendant(of: day, matching: find.byType(Scrollable)))
        .where((element) =>
            (element.widget as Scrollable).axisDirection == AxisDirection.down)
        .map((element) => find.byWidget(element.widget))
        .first;
    final scrollState = tester.state<ScrollableState>(verticalScrollable);
    final initialOffset = scrollState.position.pixels;

    await tester.drag(
      verticalScrollable,
      const Offset(0, -160),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    final mouseOffset = scrollState.position.pixels;
    expect(mouseOffset, greaterThan(initialOffset));

    await tester.drag(
      verticalScrollable,
      const Offset(0, -120),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(scrollState.position.pixels, greaterThan(mouseOffset));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a schedule event still opens its detail dialog',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpSchedule(tester);

    final day = tester.state<DayViewState<Map<String, dynamic>>>(
      find.byType(DayView<Map<String, dynamic>>),
    );
    final eventDate = day.currentDate;
    tester
        .widget<DayView<Map<String, dynamic>>>(
          find.byType(DayView<Map<String, dynamic>>),
        )
        .controller!
        .add(CalendarEventData<Map<String, dynamic>>(
          title: 'Môn kiểm thử',
          date: eventDate,
          startTime:
              DateTime(eventDate.year, eventDate.month, eventDate.day, 3),
          endTime: DateTime(eventDate.year, eventDate.month, eventDate.day, 4),
          color: Colors.blue,
          event: const {
            'is_exam': false,
            'room': 'Phòng 101',
            'lecturer': 'Giảng viên kiểm thử',
            'start_time': '03:00',
            'end_time': '04:00',
            'subjects': {
              'subject_name': 'Môn kiểm thử',
              'subject_code': 'TEST101',
            },
          },
        ));
    await tester.pumpAndSettle();

    final eventTile = find.text('Môn kiểm thử').first;
    await tester.tap(eventTile, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('TEST101'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Phòng 101')),
        findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
