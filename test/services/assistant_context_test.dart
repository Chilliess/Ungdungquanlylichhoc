import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/services/assistant_context.dart';
import 'package:untitled/services/chat_history.dart';

void main() {
  test('long context keeps recent complete turns within server limits', () {
    final messages = List.generate(
        25,
        (i) => {
              'role': i.isEven ? 'user' : 'assistant',
              'content': '$i${List.filled(1998, '"').join()}',
            });
    final original = jsonEncode(messages);
    final context = assistantContext(messages, webSearch: true);
    expect(context.first['role'], 'user');
    expect(context.last, messages.last);
    expect(context.length, lessThanOrEqualTo(12));
    expect(jsonEncode({'messages': context, 'web_search': true}).length,
        lessThan(30000));
    expect(jsonEncode(messages), original);
  });

  test('oversized old reply does not lose latest question', () {
    final messages = [
      {'role': 'user', 'content': 'Câu trước'},
      {'role': 'assistant', 'content': List.filled(6001, 'a').join()},
      {'role': 'user', 'content': 'Câu mới'},
    ];
    expect(assistantContext(messages), [messages.last]);
  });

  test('history ignores damaged entries and sorts newest first', () async {
    final good = {
      'id': 'old',
      'title': 'Ôn thi',
      'updated': '2026-11-03T10:00:00',
      'messages': [
        {'role': 'user', 'content': 'Toán'}
      ],
    };
    SharedPreferences.setMockInitialValues({
      ChatHistory.key('owner'): jsonEncode([
        good,
        {...good, 'id': 'broken', 'updated': 'bad'},
        {
          ...good,
          'id': 'invalid',
          'messages': [
            {'role': 'system'}
          ]
        },
        {
          ...good,
          'id': 'new',
          'updated': '2026-11-04T10:00:00',
          'web_search': true
        },
      ]),
    });
    final saved = await ChatHistory.load('owner');
    expect(saved.map((t) => t['id']), ['new', 'old']);
    expect(saved.first['web_search'], isTrue);
    expect(await ChatHistory.load('other'), isEmpty);
  });
}
