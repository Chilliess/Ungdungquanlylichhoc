import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/screen/lesson_categories.dart';

void main() {
  Future<void> pumpField(WidgetTester tester, LessonCategoryStore store) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var value = '';
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
      builder: (context, setState) => LessonCategoryField(
          value: value,
          store: store,
          onChanged: (selected) => setState(() => value = selected)),
    ))));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('lesson-category-chip')));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> blur(WidgetTester tester) async {
    await tester.tap(find.text('Thẻ phân loại'));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('category-done')));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
      'empty tag is transparent and creating on blur selects a reusable tag',
      (tester) async {
    final store = MemoryLessonCategoryStore();
    await pumpField(tester, store);
    expect(tester.widget<InputChip>(find.byType(InputChip)).backgroundColor,
        Colors.transparent);
    await open(tester);
    await tester.enterText(
        find.byKey(const ValueKey('category-name')), 'Thực hành');
    await blur(tester);
    expect(await store.load(), ['Thực hành']);
    expect(find.text('Thực hành'), findsOneWidget);
    await done(tester);
    expect(find.text('Thực hành'), findsOneWidget);
    expect(tester.widget<InputChip>(find.byType(InputChip)).backgroundColor,
        isNot(Colors.transparent));
    await open(tester);
    expect(
        find.descendant(
            of: find.byType(Dialog), matching: find.text('Thực hành')),
        findsOneWidget);
    await done(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('renaming on blur and deleting update the selected chip',
      (tester) async {
    final store = MemoryLessonCategoryStore(['Lý thuyết']);
    await pumpField(tester, store);
    await open(tester);
    await tester.tap(find.text('Lý thuyết'));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
    await open(tester);
    await tester.tap(find.byTooltip('Đổi tên Lý thuyết'));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
        find.byKey(const ValueKey('category-name')), 'Học nhóm');
    await blur(tester);
    expect(await store.load(), ['Học nhóm']);
    await done(tester);
    expect(find.text('Học nhóm'), findsOneWidget);
    await open(tester);
    await tester.tap(find.byTooltip('Xóa Học nhóm'));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
    await done(tester);
    expect(await store.load(), isEmpty);
    expect(find.text('Chọn nhãn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duplicate names are rejected and pending name saves when closing',
      (tester) async {
    final store = MemoryLessonCategoryStore(['Thực hành']);
    await pumpField(tester, store);
    await open(tester);
    await tester.enterText(
        find.byKey(const ValueKey('category-name')), ' thực hành ');
    await blur(tester);
    expect(find.text('Tên nhãn đã tồn tại.'), findsOneWidget);
    expect((await store.load()).length, 1);
    await tester.enterText(
        find.byKey(const ValueKey('category-name')), 'Ôn tập');
    await done(tester);
    expect((await store.load()).contains('Ôn tập'), isTrue);
    expect(find.text('Ôn tập'), findsOneWidget);
  });
  testWidgets('clearing a chip does not delete the saved tag', (tester) async {
    final store = MemoryLessonCategoryStore(['Học nhóm']);
    await pumpField(tester, store);
    await open(tester);
    await tester.tap(find.text('Học nhóm'));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
    final chip = tester.widget<InputChip>(find.byType(InputChip));
    chip.onDeleted!();
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Chọn nhãn'), findsOneWidget);
    expect(await store.load(), ['Học nhóm']);
  });
  testWidgets(
      'color can be chosen before blur and changed without renaming the tag',
      (tester) async {
    final store = MemoryLessonCategoryStore();
    await pumpField(tester, store);
    await open(tester);
    await tester.enterText(
        find.byKey(const ValueKey('category-name')), 'Ôn bài');
    final purple = find.byKey(const ValueKey('category-color-Tím'));
    await tester.ensureVisible(purple);
    await tester.tap(purple);
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
    expect(await store.load(), isEmpty);
    await blur(tester);
    expect(store.colorOf('Ôn bài'), const Color(0xFF7E57C2));
    await done(tester);
    final chip = tester.widget<InputChip>(find.byType(InputChip));
    expect((chip.avatar! as Icon).color, const Color(0xFF7E57C2));
    await open(tester);
    await tester.tap(find.byTooltip('Đổi tên Ôn bài'));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
    final blue = find.byKey(const ValueKey('category-color-Xanh dương'));
    await tester.ensureVisible(blue);
    await tester.tap(blue);
    await blur(tester);
    expect(await store.load(), ['Ôn bài']);
    expect(store.colorOf('Ôn bài'), const Color(0xFF1E88E5));
    await done(tester);
    expect(
        (tester.widget<InputChip>(find.byType(InputChip)).avatar! as Icon)
            .color,
        const Color(0xFF1E88E5));
    expect(tester.takeException(), isNull);
  });
}
