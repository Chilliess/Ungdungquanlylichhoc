import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatHistory {
  static String key(String userId) => 'chat_history_v1_$userId';
  static Future<List<Map<String, dynamic>>> load(String userId) async {
    final raw = (await SharedPreferences.getInstance()).getString(key(userId));
    return raw == null
        ? []
        : List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
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
