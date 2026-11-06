import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/homescreen.dart';
import 'package:untitled/models/home_models.dart';
import 'package:untitled/services/home_service.dart';
import 'package:untitled/services/study_data.dart';
import 'package:untitled/theme/app_theme.dart';
import 'package:untitled/widgets/assistant_overlay.dart';

class _PreviewService extends HomeService {
  @override
  Future<HomeSnapshot> loadSnapshot({DateTime? now}) async {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    Map<String, dynamic> row(
            String id, String name, DateTime date, String start) =>
        {
          'id': id,
          'subject_id': id,
          'recurrence': 'none',
          'start_date': DateFormat('yyyy-MM-dd').format(date),
          'end_date': DateFormat('yyyy-MM-dd').format(date),
          'start_time': start,
          'end_time': '16:00',
          'room': 'Phòng A201 · Cơ sở 1',
          'subjects': {'subject_name': name, 'color_code': '#6254D9'},
        };
    return HomeService.buildSnapshot(username: 'Nguyễn Minh Anh', subjects: [
      {'id': 'a', 'subject_name': 'Toán cao cấp'}
    ], schedules: [
      row('a', 'Toán cao cấp', today, '09:00'),
      row('b', 'Thiết kế giao diện', today, '14:00'),
      row('c', 'Lập trình hướng đối tượng', tomorrow, '13:00')
    ], exams: [], reminders: []);
  }
}

class _FailingService extends HomeService {
  @override
  Future<HomeSnapshot> loadSnapshot({DateTime? now}) async =>
      throw StateError('offline');
}

class _RacingService extends HomeService {
  int calls = 0;
  final older = Completer<HomeSnapshot>();
  final newer = Completer<HomeSnapshot>();
  static HomeSnapshot snapshot(String name) => HomeService.buildSnapshot(
      username: name, subjects: [], schedules: [], exams: [], reminders: []);
  @override
  Future<HomeSnapshot> loadSnapshot({DateTime? now}) {
    calls++;
    if (calls == 1) return Future.value(snapshot('Ban đầu'));
    return calls == 2 ? older.future : newer.future;
  }
}

class _SwitchingService extends HomeService {
  final changes = StreamController<String?>();
  final nextAccount = Completer<HomeSnapshot>();
  bool switching = false;
  @override
  String? get accountId => 'a';
  @override
  Stream<String?> get accountChanges => changes.stream;
  @override
  Future<HomeSnapshot> loadSnapshot({DateTime? now}) => switching
      ? nextAccount.future
      : Future.value(_RacingService.snapshot('Tài khoản A'));
}

Future<void> _preview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('UI_PREVIEWS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('preview')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('artifacts/ui');
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('task tab keeps bottom navigation and hides the home greeting',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: HomeScreen(service: _PreviewService())));
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Minh Anh'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Công việc')));
    await tester.pumpAndSettle();
    expect(find.text('Việc cần làm'), findsOneWidget);
    expect(find.text('Nguyễn Minh Anh'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2);
    await tester.tap(find.descendant(
        of: find.byType(NavigationBar), matching: find.text('Trang chủ')));
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Minh Anh'), findsOneWidget);
    expect(find.text('Việc cần làm'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  setUpAll(() async {
    await initializeDateFormatting('vi_VN');
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:54321', anonKey: 'test');
    if (const bool.fromEnvironment('UI_PREVIEWS')) {
      final fonts = FontLoader('PreviewSans');
      fonts.addFont(File('C:/Windows/Fonts/segoeui.ttf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
      await fonts.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(File(
              'C:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
      await icons.load();
    }
  });

  testWidgets('Chat tab and floating robot share a single conversation',
      (tester) async {
    final originalShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      final accounts = StreamController<String?>();
      addTearDown(accounts.close);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(RepaintBoundary(
          key: const ValueKey('preview'),
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: const bool.fromEnvironment('UI_PREVIEWS')
                  ? studyTheme(Brightness.light).copyWith(
                      textTheme: studyTheme(Brightness.light)
                          .textTheme
                          .apply(fontFamily: 'PreviewSans'))
                  : studyTheme(Brightness.light),
              builder: (_, child) => AssistantOverlay(
                  initialUserId: 'a',
                  accountChanges: accounts.stream,
                  sendMessage: (_) async =>
                      'Mình sẽ giúp bạn chia nhỏ nội dung ôn tập. Bạn thi môn nào và ngày nào?',
                  child: child!),
              home: HomeScreen(service: _PreviewService()))));
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Minh Anh'), findsOneWidget);
      expect(find.text('Thống kê'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(NavigationBar), matching: find.text('Thống kê')),
          findsNothing);
      await _preview(tester, 'home-desktop');
      await tester.tap(find.text('Chat AI'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assistant-dialog')), findsOneWidget);
      expect(find.byTooltip('Tài khoản'), findsNothing);
      expect(find.byKey(const ValueKey('home-notifications')), findsNothing);
      expect(find.text('Nguyễn Minh Anh'), findsNothing);
      await tester.tap(find.text('Đồng ý và bắt đầu'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byType(TextField), 'Giúp tôi ôn thi có kế hoạch.');
      await tester.tap(find.byTooltip('Gửi'));
      await tester.pumpAndSettle();
      await _preview(tester, 'chat-desktop');
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);
      await tester.tap(find.text('Trang chủ'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('assistant-dialog')), findsNothing);
      await tester.tap(find.byTooltip('Mở trợ lý AI'));
      await tester.pumpAndSettle();
      expect(find.text('Giúp tôi ôn thi có kế hoạch.'), findsOneWidget);
      await tester.tap(find.byTooltip('Thu gọn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chat AI'));
      await tester.pumpAndSettle();
      expect(find.text('Giúp tôi ôn thi có kế hoạch.'), findsOneWidget);
      await tester.tap(find.text('Trang chủ'));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpAndSettle();
      await _preview(tester, 'home-mobile');
      await tester.tap(find.byTooltip('Mở trợ lý AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lịch sử trò chuyện'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trò chuyện mới'));
      await tester.pumpAndSettle();
      expect(find.text('Trợ lý học tập'), findsOneWidget);
      expect(find.text('Lên kế hoạch ôn thi'), findsOneWidget);
      expect(find.text('Chia nhỏ bài tập khó'), findsOneWidget);
      expect(find.textContaining('Phản hồi mô phỏng'), findsNothing);
      await _preview(tester, 'mini-ai-mobile');
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      await tester.pumpAndSettle();
      await _preview(tester, 'mini-ai-desktop');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDisableShadows = originalShadows;
    }
  });

  testWidgets('load failure never claims the user has no lessons',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: HomeScreen(service: _FailingService())));
    await tester.pumpAndSettle();
    expect(find.text('Chưa xác định được lịch hôm nay'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-empty-today')), findsNothing);
    expect(find.text('Không tải được lịch. Vui lòng thử lại.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'local writes refresh home and late responses cannot replace newer data',
      (tester) async {
    final service = _RacingService();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(service: service)));
    await tester.pumpAndSettle();
    studyDataChanged();
    await tester.pump(const Duration(milliseconds: 150));
    studyDataChanged();
    await tester.pump(const Duration(milliseconds: 150));
    expect(service.calls, 3);
    service.newer.complete(_RacingService.snapshot('Tên mới'));
    await tester.pumpAndSettle();
    service.older.complete(_RacingService.snapshot('Tên cũ'));
    await tester.pumpAndSettle();
    expect(find.text('Tên mới'), findsOneWidget);
    expect(find.text('Tên cũ'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching accounts clears old data even after a local refresh',
      (tester) async {
    final service = _SwitchingService();
    addTearDown(service.changes.close);
    await tester.pumpWidget(MaterialApp(home: HomeScreen(service: service)));
    await tester.pumpAndSettle();
    studyDataChanged();
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
    service.switching = true;
    service.changes.add('b');
    // Deliver the async auth event, then render its cleared snapshot. Do not
    // pumpAndSettle while the new account deliberately has an in-flight load.
    await tester.pump();
    await tester.pump();
    expect(find.text('Tài khoản A'), findsNothing);
    service.nextAccount.complete(_RacingService.snapshot('Tài khoản B'));
    await tester.pumpAndSettle();
    expect(find.text('Tài khoản B'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
