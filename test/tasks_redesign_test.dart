import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/screen/tasks_screen.dart';
import 'package:untitled/services/learning_store.dart';

class _MemoryStore extends LearningStore {
  int saves = 0;
  @override
  Future<void> load() async {}
  @override
  Future<void> save() async {
    saves++;
    notifyListeners();
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:54321', anonKey: 'test');
  });

  _MemoryStore store() {
    final result = _MemoryStore();
    result.tasks = [
      {
        'id': 'report',
        'title': 'Báo cáo đồ án liên ngành',
        'subject': 'Đồ án liên ngành',
        'deadline':
            DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        'minutes': 180,
        'difficulty': 3,
        'done': false,
      }
    ];
    return result;
  }

  Future<void> pump(WidgetTester tester, _MemoryStore data,
      {Future<StudyPlan> Function(List<int>)? plan}) async {
    await tester.pumpWidget(MaterialApp(
        home: TasksScreen(
            embedded: true,
            store: data,
            loadPlan: plan ?? (_) async => const StudyPlan([], 0))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
  }

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1000, 850)
  ]) {
    testWidgets('task layout has no welcome header and fits $size',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final data = store();
      final date = DateTime.now().add(const Duration(days: 1));
      await pump(tester, data,
          plan: (_) async => StudyPlan([
                {
                  'id': 'block',
                  'taskId': 'report',
                  'title': 'Báo cáo đồ án liên ngành',
                  'start': DateTime(date.year, date.month, date.day, 19)
                      .toIso8601String(),
                  'end': DateTime(date.year, date.month, date.day, 19, 50)
                      .toIso8601String(),
                }
              ], 0));
      expect(find.text('Việc cần làm'), findsOneWidget);
      expect(find.textContaining('Xin chào'), findsNothing);
      expect(find.text('GÓC HỌC TẬP CỦA BẠN'), findsNothing);
      await tester.scrollUntilVisible(
          find.byKey(const ValueKey('task-free-slot')), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Ngày mai, 19:00 – 19:50'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'checkbox persists completion and removes only future planned blocks',
      (tester) async {
    final data = store();
    final past =
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    final future =
        DateTime.now().add(const Duration(days: 1)).toIso8601String();
    data.blocks = [
      {'id': 'past', 'taskId': 'report', 'start': past},
      {'id': 'future', 'taskId': 'report', 'start': future}
    ];
    data.logs = [
      {'id': 'log', 'taskId': 'report', 'minutes': 25}
    ];
    await pump(tester, data);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(data.tasks.single['done'], isTrue);
    expect(data.saves, 1);
    expect(data.blocks.single['id'], 'past');
    expect(data.logs.single['minutes'], 25);
    await tester.tap(find.text('Đã xong · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Báo cáo đồ án liên ngành'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('calendar load failure never invents a free time',
      (tester) async {
    await pump(tester, store(), plan: (_) async => throw StateError('offline'));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('task-free-slot')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Chưa tải đủ lịch'), findsOneWidget);
    expect(find.textContaining('19:00'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('add work opens the existing editor', (tester) async {
    await pump(tester, store());
    await tester.tap(find.widgetWithText(FilledButton, 'Công việc'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditor), findsOneWidget);
    expect(find.text('Thêm công việc'), findsOneWidget);
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
