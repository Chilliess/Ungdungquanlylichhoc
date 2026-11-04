import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatHistory {
  static String key(String userId) => 'chat_history_v1_$userId';
  static Future<List<Map<String, dynamic>>> load(String userId) async {
    final raw = (await SharedPreferences.getInstance()).getString(key(userId));
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid chat history');
    // A damaged entry must not prevent opening other saved conversations.
    return decoded
        .whereType<Map>()
        .where((thread) {
          final messages = thread['messages'];
          return thread['id'] is String &&
              thread['title'] is String &&
              thread['updated'] is String &&
              DateTime.tryParse(thread['updated'] as String) != null &&
              messages is List &&
              messages.every((message) =>
                  message is Map &&
                  ['user', 'assistant'].contains(message['role']) &&
                  message['content'] is String);
        })
        .map((thread) => Map<String, dynamic>.from(thread))
        .toList()
      ..sort((a, b) => DateTime.parse(b['updated'] as String)
          .compareTo(DateTime.parse(a['updated'] as String)));
  }

  static Future<void> save(
      String userId, List<Map<String, dynamic>> threads) async {
    final encoded = jsonEncode(threads);
    if (!await (await SharedPreferences.getInstance())
        .setString(key(userId), encoded)) {
      throw StateError('Cannot save conversation');
    }
  }
}
