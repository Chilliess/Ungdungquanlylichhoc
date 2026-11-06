import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/screen/tasks_screen.dart';
import 'package:untitled/services/learning_store.dart';

void main() {
  test('task label follows a renamed subject while legacy task text survives',
      () {
    final store = LearningStore();
    store.subjects = [
      {'id': 'math', 'subject_name': 'Toán nâng cao'}
    ];
    expect(store.subjectName({'subjectId': 'math', 'subject': 'Tên cũ'}),
        'Toán nâng cao');
    expect(store.subjectName({'subjectId': 'deleted', 'subject': 'Môn đã học'}),
        'Môn đã học');
    expect(store.subjectName({}), 'Cá nhân');
  });
  testWidgets('task editor stores selected subject ID and name',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      saved = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (_) => const TaskEditor(subjects: [
                                {'id': 'math', 'subject_name': 'Toán rời rạc'}
                              ]));
                    },
                    child: const Text('Mở'))))));
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Ôn chương 3');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toán rời rạc').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lưu'));
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(saved?['subjectId'], 'math');
    expect(saved?['subject'], 'Toán rời rạc');
    expect(tester.takeException(), isNull);
  });
}
