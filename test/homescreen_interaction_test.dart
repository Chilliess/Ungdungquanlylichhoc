import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/homescreen.dart';
import 'package:untitled/models/home_models.dart';
import 'package:untitled/screen/settings.dart';
import 'package:untitled/screen/statistical.dart';
import 'package:untitled/screen/view_schedule_screen.dart';
import 'package:untitled/services/home_service.dart';
import 'package:untitled/screen/lesson_editor.dart';

class _FakeHomeService extends HomeService {
  int loadCount = 0;

  @override
  Future<HomeSnapshot> loadSnapshot({DateTime? now}) async {
    loadCount++;
    return const HomeSnapshot.empty();
  }
}

class _DatedHomeService extends _FakeHomeService {
  final now = DateTime.now();
  late final first = DateTime(now.year, now.month, now.day + 2);
  late final second = DateTime(now.year, now.month, now.day + 3);
  @override
  Future<HomeSnapshot> loadSnapshot({DateTime? now}) async {
    Map<String, dynamic> row(DateTime date, String name, String id) => {
          'id': id,
          'day_of_week': [date.weekday + 1],
          'start_date': DateFormat('yyyy-MM-dd').format(date),
          'end_date': DateFormat('yyyy-MM-dd').format(date),
          'start_time': '07:00',
          'end_time': '09:00',
          'room': 'A101',
          'subjects': {'subject_name': name},
        };
    return HomeService.buildSnapshot(subjects: [], schedules: [
      row(first, 'Buổi gần nhất', 'one'),
      row(second, 'Buổi ngày khác', 'two'),
      row(first, 'Buổi cùng ngày', 'three'),
    ], exams: [], reminders: [], now: this.now);
  }
}

Future<void> _pumpHome(WidgetTester tester, _FakeHomeService service) async {
  await tester.binding.setSurfaceSize(const Size(400, 800));
  await tester.pumpWidget(
    MaterialApp(home: HomeScreen(service: service)),
  );
  await tester.pumpAndSettle();
}

Future<void> _mouseTap(WidgetTester tester, Finder target) async {
  final position = tester.getCenter(target);
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: position);
  await tester.pump();
  await mouse.down(position);
  await mouse.up();
  await tester.pumpAndSettle();
  await mouse.removePointer();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('vi_VN', null);
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets('home prioritizes today and removes redundant summary sections',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, _FakeHomeService());

    final welcome = tester.getRect(find.text('Xin chào!'));
    final today = tester.getRect(find.text('Hôm nay'));
    expect(today.top, greaterThan(welcome.bottom));
    expect(find.text('Buổi hôm nay'), findsNothing);
    expect(find.text('Thời khóa biểu tuần'), findsNothing);
    expect(find.byType(GridView), findsNothing);
    expect(
        tester.getSize(find.byKey(const ValueKey('home-empty-today'))).height,
        lessThan(150));
    expect(tester.takeException(), isNull);
  });

  testWidgets('home list can be dragged with a mouse and touch',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, _FakeHomeService());

    await tester.binding.setSurfaceSize(const Size(320, 320));
    await tester.pumpAndSettle();
    final list = find.byType(ListView).first;
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    final startOffset = scrollable.position.pixels;

    await tester.drag(
      list,
      const Offset(0, -260),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(startOffset));

    final afterMouseDrag = scrollable.position.pixels;
    await tester.drag(
      list,
      const Offset(0, -180),
      kind: PointerDeviceKind.touch,
    );
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(afterMouseDrag));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mouse can hover over bottom navigation without an exception',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, _FakeHomeService());

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.text('Lịch học')));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Cài đặt').last));
    await tester.pump();

    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('bottom navigation items respond and open their screens',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _FakeHomeService();
    await _pumpHome(tester, service);

    await _mouseTap(tester, find.text('Lịch học'));
    expect(find.byType(ViewScheduleScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _mouseTap(tester, find.text('Thống kê').last);
    expect(find.byType(StatisticalScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await _mouseTap(tester, find.text('Cài đặt').last);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    final loadCountBeforeHomeTap = service.loadCount;
    await _mouseTap(tester, find.text('Trang chủ'));
    expect(service.loadCount, greaterThan(loadCountBeforeHomeTap));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'desktop content is capped and centered with compact management links',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, _FakeHomeService());
    await tester.binding.setSurfaceSize(const Size(1920, 1000));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('home-content')));
    expect(rect.width, 1040);
    expect(rect.center.dx, 960);
    expect(tester.getSize(find.byType(ListTile).first).height, lessThan(85));
    expect(tester.takeException(), isNull);
  });
  testWidgets('add lesson opens the calendar editor directly', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, _FakeHomeService());
    await tester.tap(find.byKey(const ValueKey('home-add-lesson')));
    await tester.pumpAndSettle();
    expect(find.byType(LessonEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'upcoming selects the nearest scheduled day and opens the selected date',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _DatedHomeService();
    await _pumpHome(tester, service);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    await tester.pumpAndSettle();
    String label(DateTime date) =>
        '${WeekdayUtils.shortName(date.weekday + 1)}, ${DateFormat('dd/MM/yyyy').format(date)}';
    expect(find.text(label(service.first)), findsOneWidget);
    expect(find.text('Buổi gần nhất'), findsOneWidget);
    expect(find.text('Buổi cùng ngày'), findsOneWidget);
    expect(find.text('Buổi ngày khác'), findsNothing);
    final dateButton = find.byKey(const ValueKey('home-upcoming-date'));
    expect(
        tester.getRect(find.byKey(const ValueKey('home-open-upcoming'))).right,
        closeTo(
            tester
                .getRect(find.byKey(const ValueKey('home-upcoming-header')))
                .right,
            0.5));
    await tester.ensureVisible(dateButton);
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    final calendar =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    final tomorrow =
        DateTime(service.now.year, service.now.month, service.now.day + 1);
    expect(calendar.selectableDayPredicate, isNull);
    calendar.onDateChanged(tomorrow);
    await tester.pump();
    final confirm = MaterialLocalizations.of(
            tester.element(find.byType(CalendarDatePicker)))
        .okButtonLabel;
    await tester.tap(find.text(confirm));
    await tester.pumpAndSettle();
    expect(find.text(label(tomorrow)), findsOneWidget);
    expect(find.text('Ngày này chưa có lịch trình.'), findsOneWidget);
    expect(find.text('Buổi gần nhất'), findsNothing);
    await tester.tap(dateButton);
    await tester.pumpAndSettle();
    final nextCalendar =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    nextCalendar.onDateChanged(service.second);
    await tester.pump();
    final ok = MaterialLocalizations.of(
            tester.element(find.byType(CalendarDatePicker)))
        .okButtonLabel;
    await tester.tap(find.text(ok));
    await tester.pumpAndSettle();
    expect(find.text(label(service.second)), findsOneWidget);
    expect(find.text('Buổi ngày khác'), findsOneWidget);
    expect(find.text('Buổi gần nhất'), findsNothing);
    final open = find.byKey(const ValueKey('home-open-upcoming'));
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ViewScheduleScreen>(find.byType(ViewScheduleScreen))
            .initialDate,
        service.second);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reminders bell is beside account and navigation sections have separators',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _pumpHome(tester, _FakeHomeService());
    final bell = tester.getRect(find.byKey(const ValueKey('home-reminders')));
    final account = tester.getRect(find.byTooltip('Tài khoản'));
    expect(bell.right, lessThanOrEqualTo(account.left));
    expect(bell.center.dy, account.center.dy);
    expect(find.text('Nhắc nhở'), findsNothing);
    expect(find.byType(VerticalDivider), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
