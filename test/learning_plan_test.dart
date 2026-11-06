import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/services/chat_history.dart';
import 'package:untitled/services/learning_store.dart';

void main() {
  test(
      'planner respects fixed events, deadline, availability and rest between sessions',
      () {
    final now = DateTime(2026, 11, 4, 17);
    final fixed =
        BusySlot(DateTime(2026, 11, 4, 18), DateTime(2026, 11, 4, 19));
    final deadline = DateTime(2026, 11, 4, 22);
    final result = planStudy(tasks: [
      {
        'id': 'a',
        'title': 'Ôn thi',
        'subject': 'Toán',
        'minutes': 130,
        'difficulty': 3,
        'deadline': deadline.toIso8601String()
      }
    ], busy: [
      fixed
    ], now: now);
    expect(result.unscheduledMinutes, 0);
    int total = 0;
    DateTime? previous;
    for (final block in result.blocks) {
      final start = DateTime.parse(block['start']),
          end = DateTime.parse(block['end']);
      expect(fixed.overlaps(start, end), false);
      expect(start.isBefore(now), false);
      expect(end.isAfter(deadline), false);
      expect(start.hour, greaterThanOrEqualTo(18));
      expect(end.hour, lessThanOrEqualTo(22));
      if (previous != null) {
        expect(start.difference(previous).inMinutes, greaterThanOrEqualTo(10));
      }
      previous = end;
      total += end.difference(start).inMinutes;
    }
    expect(total, 130);
  });
  test('planner explains unavailable minutes without placing past deadline',
      () {
    final now = DateTime(2026, 11, 4, 17);
    final result = planStudy(tasks: [
      {
        'id': 'a',
        'title': 'Ôn thi',
        'subject': 'Toán',
        'minutes': 120,
        'difficulty': 1,
        'deadline': DateTime(2026, 11, 4, 17, 30).toIso8601String()
      }
    ], busy: [], now: now);
    expect(result.blocks, isEmpty);
    expect(result.unscheduledMinutes, 120);
  });
  test('chat persists by account and deletion does not affect another account',
      () async {
    SharedPreferences.setMockInitialValues({});
    final a = [
      {
        'id': 'a',
        'title': 'Ôn thi',
        'updated': '2026-11-04T12:00:00',
        'messages': [
          {'role': 'user', 'content': 'Xin chào'}
        ]
      }
    ];
    await ChatHistory.save('alice', a);
    await ChatHistory.save('bob', [
      {
        'id': 'b',
        'title': 'Bài tập',
        'updated': '2026-11-04T13:00:00',
        'messages': []
      }
    ]);
    expect((await ChatHistory.load('alice')).single['title'], 'Ôn thi');
    await ChatHistory.save('alice', []);
    expect(await ChatHistory.load('alice'), isEmpty);
    expect((await ChatHistory.load('bob')).single['title'], 'Bài tập');
  });
}
