import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/screen/lesson_editor.dart';

void main() {
  Future<void> openEditor(
      WidgetTester tester, Future<void> Function(LessonDraft) save,
      {LessonDraft? initial, bool manageRecurrence = false}) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => LessonEditor(
                            initialDate: DateTime(2026, 11, 2),
                            initial: initial,
                            manageRecurrence: manageRecurrence,
                            onSave: save)),
                    child: const Text('Mở form'))))));
    await tester.tap(find.text('Mở form'));
    await tester.pumpAndSettle();
  }

  Future<void> tapField(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    if (key == 'lesson-save' &&
        find.byKey(const ValueKey('confirm-action')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('confirm-action')));
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
      'recurrence dropdown saves monthly rule and supports turning repeat off',
      (tester) async {
    LessonDraft? saved;
    final initial = LessonDraft(
        title: 'Toán',
        location: 'A6',
        date: DateTime(2026, 11, 2),
        start: const TimeOfDay(hour: 7, minute: 0),
        end: const TimeOfDay(hour: 9, minute: 0));
    await openEditor(tester, (draft) async => saved = draft,
        initial: initial, manageRecurrence: true);
    await tapField(tester, 'lesson-recurrence');
    await tester.tap(find.text('Hằng tháng').last);
    await tester.pumpAndSettle();
    expect(find.text('Không giới hạn'), findsOneWidget);
    await tapField(tester, 'lesson-save');
    expect(saved!.recurrence, 'monthly');
    expect(saved!.repeatUntil, isNull);
    await openEditor(tester, (draft) async => saved = draft,
        initial: saved, manageRecurrence: true);
    await tapField(tester, 'lesson-recurrence');
    await tester.tap(find.text('Không lặp').last);
    await tester.pumpAndSettle();
    expect(find.text('Không giới hạn'), findsNothing);
    await tapField(tester, 'lesson-save');
    expect(saved!.recurrence, 'none');
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing dirty form requires discard and cancel preserves input',
      (tester) async {
    await openEditor(tester, (_) async {});
    await tester.enterText(find.byKey(const ValueKey('lesson-title')), 'Toán');
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget);
    await tester.tap(find.text('Tiếp tục sửa'));
    await tester.pumpAndSettle();
    expect(find.text('Toán'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bỏ thay đổi'));
    await tester.pumpAndSettle();
    expect(find.byType(LessonEditor), findsNothing);
  });

  testWidgets('recurring confirmation states scope and cancel does not save',
      (tester) async {
    var writes = 0;
    await openEditor(tester, (_) async => writes++,
        manageRecurrence: true,
        initial: LessonDraft(
            title: 'Toán',
            location: 'A6',
            date: DateTime(2026, 11, 3),
            start: const TimeOfDay(hour: 7, minute: 0),
            end: const TimeOfDay(hour: 9, minute: 0),
            recurrence: 'weekly'));
    await tester.tap(find.byKey(const ValueKey('lesson-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('bao gồm các buổi đã qua'), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Hủy')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.byType(LessonEditor), findsOneWidget);
  });

  testWidgets('required fields prevent saving empty or whitespace data',
      (tester) async {
    var calls = 0;
    await openEditor(tester, (_) async => calls++);
    await tester.enterText(find.byKey(const ValueKey('lesson-title')), '   ');
    await tapField(tester, 'lesson-save');
    expect(calls, 0);
    expect(find.text('Vui lòng nhập tên môn học'), findsOneWidget);
    expect(find.text('Vui lòng nhập địa điểm'), findsOneWidget);
    expect(find.text('Vui lòng chọn giờ'), findsNWidgets(2));
  });

  testWidgets('wheel time selection saves with optional fields empty',
      (tester) async {
    LessonDraft? saved;
    await openEditor(tester, (draft) async => saved = draft,
        initial: LessonDraft(
            title: '',
            location: '',
            date: DateTime(2026, 11, 2),
            start: const TimeOfDay(hour: 7, minute: 0),
            end: const TimeOfDay(hour: 9, minute: 0)));
    await tester.enterText(
        find.byKey(const ValueKey('lesson-title')), 'Lập trình');
    await tapField(tester, 'lesson-start');
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(
        tester
            .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
            .use24hFormat,
        isTrue);
    await tester.drag(find.byType(CupertinoPicker).first, const Offset(0, -32));
    await tester.pumpAndSettle();
    await tapField(tester, 'lesson-confirm-time');
    await tapField(tester, 'lesson-end');
    await tapField(tester, 'lesson-confirm-time');
    await tester.ensureVisible(find.byKey(const ValueKey('lesson-location')));
    await tester.enterText(
        find.byKey(const ValueKey('lesson-location')), 'A203');
    await tapField(tester, 'lesson-save');
    expect(saved, isNotNull);
    expect(saved!.start.hour, 8);
    expect(saved!.end.hour, 9);
    expect(saved!.date, DateTime(2026, 11, 2));
    expect(saved!.notes, isEmpty);
    expect(saved!.category, isEmpty);
    expect(find.byType(LessonEditor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects end time before start time', (tester) async {
    var calls = 0;
    await openEditor(tester, (_) async => calls++,
        initial: LessonDraft(
            title: 'Toán',
            date: DateTime(2026, 11, 2),
            start: const TimeOfDay(hour: 10, minute: 0),
            end: const TimeOfDay(hour: 9, minute: 0),
            location: 'A101'));
    await tapField(tester, 'lesson-save');
    expect(find.text('Giờ kết thúc phải sau giờ bắt đầu'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets(
      'editing preserves notes and category and retains input on save failure',
      (tester) async {
    LessonDraft? attempted;
    await openEditor(tester, (draft) async {
      attempted = draft;
      throw Exception('Không có kết nối');
    },
        initial: LessonDraft(
            title: 'Toán',
            date: DateTime(2026, 11, 2),
            start: const TimeOfDay(hour: 7, minute: 0),
            end: const TimeOfDay(hour: 9, minute: 0),
            location: 'A101',
            notes: 'Mang máy tính',
            category: 'Lý thuyết'));
    await tester.enterText(
        find.byKey(const ValueKey('lesson-title')), 'Toán nâng cao');
    await tapField(tester, 'lesson-save');
    expect(attempted!.title, 'Toán nâng cao');
    expect(attempted!.notes, 'Mang máy tính');
    expect(attempted!.category, 'Lý thuyết');
    expect(find.text('Không có kết nối'), findsOneWidget);
    expect(find.byType(LessonEditor), findsOneWidget);
    expect(find.text('Toán nâng cao'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('save parameters preserve local date and all editable information', () {
    final draft = LessonDraft(
        title: ' Toán ',
        date: DateTime(2026, 12, 31),
        start: const TimeOfDay(hour: 13, minute: 5),
        end: const TimeOfDay(hour: 15, minute: 0),
        location: ' A203 ',
        notes: ' Ghi chú ',
        category: ' Thực hành ');
    final params = draft.toParameters(
        id: 'schedule-id', occurrenceDate: DateTime(2026, 12, 30));
    expect(params['p_title'], 'Toán');
    expect(params['p_date'], '2026-12-31');
    expect(params['p_start'], '13:05');
    expect(params['p_room'], 'A203');
    expect(params['p_notes'], 'Ghi chú');
    expect(params['p_category'], 'Thực hành');
    expect(params['p_occurrence_date'], '2026-12-30');
    expect(params['p_id'], 'schedule-id');
  });
  testWidgets('grouped date field aligns with subject field', (tester) async {
    await openEditor(tester, (_) async {});
    final date = find.byKey(const ValueKey('lesson-date'));
    final title = find.byKey(const ValueKey('lesson-title'));
    final decorator = tester.widget<InputDecorator>(
        find.descendant(of: date, matching: find.byType(InputDecorator)));
    expect(decorator.decoration.border, InputBorder.none);
    expect(decorator.decoration.labelText, 'Ngày học *');
    expect(tester.getRect(date).left, tester.getRect(title).left);
    expect(tester.getRect(date).width, tester.getRect(title).width);
    expect(
        tester.getRect(date).height, closeTo(tester.getRect(title).height, 1));
    expect(find.text('02/11/2026'), findsOneWidget);
    await tapField(tester, 'lesson-date');
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
  testWidgets('category is inside the subject group and hours share a row',
      (tester) async {
    await openEditor(tester, (_) async {});
    final chip = find.byKey(const ValueKey('lesson-category-chip'));
    expect(chip, findsOneWidget);
    expect(
        tester.getRect(chip).top,
        greaterThan(
            tester.getRect(find.byKey(const ValueKey('lesson-title'))).top));
    final start = tester.getRect(find.byKey(const ValueKey('lesson-start')));
    final end = tester.getRect(find.byKey(const ValueKey('lesson-end')));
    expect(start.top, closeTo(end.top, 1));
    expect(start.right, lessThan(end.left));
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Thẻ phân loại'), findsOneWidget);
  });
  testWidgets('unselected time wheels start at the current hour and minute',
      (tester) async {
    await openEditor(tester, (_) async {});
    for (final field in ['lesson-start', 'lesson-end']) {
      final before = DateTime.now();
      await tapField(tester, field);
      final picker =
          tester.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
      final after = DateTime.now();
      final initial = picker.initialDateTime;
      expect(
          (initial.hour == before.hour && initial.minute == before.minute) ||
              (initial.hour == after.hour && initial.minute == after.minute),
          isTrue);
      await tester.tap(find.descendant(
          of: find.byType(BottomSheet), matching: find.text('Hủy')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Chọn giờ'), findsNWidgets(2));
  });
}
