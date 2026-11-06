import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Read state belongs to an account on this device, like chat history.
class NotificationReads extends ChangeNotifier {
  final Map<String, Set<String>> _read = {};
  final Map<String, Future<void>> _loading = {};
  Future<void> _writes = Future.value();
  Future<void> load(String? owner) async {
    if (owner == null || _read.containsKey(owner)) return;
    final pending = _loading[owner] ??= () async {
      final prefs = await SharedPreferences.getInstance();
      _read[owner] =
          (prefs.getStringList('notification_reads_v1:$owner') ?? []).toSet();
    }();
    try {
      await pending;
    } finally {
      if (identical(_loading[owner], pending)) _loading.remove(owner);
    }
  }

  bool isRead(String? owner, String key) =>
      owner != null && (_read[owner]?.contains(key) ?? false);
  Future<void> mark(String? owner, Iterable<String> keys) async {
    if (owner == null) return;
    final additions = keys.toList();
    final pending = _writes.catchError((Object _) {}).then((_) async {
      await load(owner);
      // Commit read state only after persistence succeeds, including retries.
      final snapshot = {..._read[owner]!, ...additions}.toList();
      if (snapshot.length > 2000) {
        snapshot.removeRange(0, snapshot.length - 2000);
      }
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(
          'notification_reads_v1:$owner', snapshot)) {
        throw StateError('Không lưu được trạng thái thông báo.');
      }
      _read[owner] = snapshot.toSet();
      notifyListeners();
    });
    _writes = pending;
    await pending;
  }

  static String key(String type, String id, DateTime start) =>
      jsonEncode([type, id, start.toIso8601String()]);
}

final notificationReads = NotificationReads();
