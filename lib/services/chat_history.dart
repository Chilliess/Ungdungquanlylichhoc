import 'dart:convert';
import 'workspace_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatHistory {
  static String key(String userId) => 'chat_history_v1_$userId';
  static final Map<String, WorkspaceCollection> _cloud = {};
  @visibleForTesting
  static void resetMemory() => _cloud.clear();
  static WorkspaceCollection _collection(String userId) =>
      _cloud.putIfAbsent(userId, () => WorkspaceCollection(userId, 'chat'));
  static bool isSynced(String userId) => _cloud[userId]?.synced ?? false;

  static Future<List<Map<String, dynamic>>> load(String userId) async {
    return _valid(await _collection(userId).load(await _local(userId)));
  }

  static Future<List<Map<String, dynamic>>> _local(String userId) async {
    final raw = (await SharedPreferences.getInstance()).getString(key(userId));
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) throw const FormatException('Invalid chat history');
    return _valid(decoded);
  }

  static List<Map<String, dynamic>> _valid(List decoded) {
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

  static Future<List<Map<String, dynamic>>> save(
      String userId, List<Map<String, dynamic>> threads) async {
    if (!_cloud.containsKey(userId)) {
      // Seed from the old local file before recording edits; do not pull first.
      final collection = _collection(userId);
      await collection.seed(await _local(userId));
    }
    final merged = _valid(await _collection(userId).save(threads));
    final encoded = jsonEncode(merged);
    if (!await (await SharedPreferences.getInstance())
        .setString(key(userId), encoded)) {
      throw StateError('Cannot save conversation');
    }
    return merged;
  }
}
