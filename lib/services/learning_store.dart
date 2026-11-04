import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final learningStore = LearningStore();

class LearningStore extends ChangeNotifier {
  String? _owner;
  bool _loaded = false;
  List<Map<String, dynamic>> tasks = [], blocks = [], logs = [];
  int goalMinutes = 600;
  Future<void> _writes = Future.value();
  static String key(String owner) => 'learning_workspace_v1_$owner';
  static String id() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> load() async {
    final owner = Supabase.instance.client.auth.currentUser?.id;
    if (_loaded && owner == _owner) return;
    _owner = owner;
    _loaded = false;
    tasks = [];
    blocks = [];
    logs = [];
    goalMinutes = 600;
    if (owner == null) {
      notifyListeners();
      return;
    }
    final raw = (await SharedPreferences.getInstance()).getString(key(owner));
    if (_owner != owner) return;
    if (raw != null) {
      final data = jsonDecode(raw) as Map;
      tasks = List<Map<String, dynamic>>.from(data['tasks'] as List);
      blocks = List<Map<String, dynamic>>.from(data['blocks'] as List);
      logs = List<Map<String, dynamic>>.from(data['logs'] as List);
      goalMinutes = data['goal'] as int? ?? 600;
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    final owner = _owner;
    if (!_loaded || owner == null ||
        owner != Supabase.instance.client.auth.currentUser?.id) {
      throw StateError('Vui lòng đăng nhập lại.');
    }
    final encoded = jsonEncode(
        {'tasks': tasks, 'blocks': blocks, 'logs': logs, 'goal': goalMinutes});
    _writes = _writes.catchError((_) {}).then((_) async {
      if (!await (await SharedPreferences.getInstance())
          .setString(key(owner), encoded)) {
        throw StateError('Không lưu được dữ liệu trên thiết bị.');
      }
    });
    await _writes;
    notifyListeners();
  }

  List<Map<String, dynamic>> get pending => tasks
      .where((t) => t['done'] != true)
      .toList()
    ..sort(
        (a, b) => (a['deadline'] as String).compareTo(b['deadline'] as String));
  int actualFor(String taskId) => logs
      .where((l) => l['taskId'] == taskId)
      .fold(0, (v, l) => v + (l['minutes'] as int));
}

class BusySlot {
  const BusySlot(this.start, this.end);
  final DateTime start, end;
  bool overlaps(DateTime a, DateTime b) => a.isBefore(end) && b.isAfter(start);
}

class StudyPlan {
  const StudyPlan(this.blocks, this.unscheduledMinutes);
  final List<Map<String, dynamic>> blocks;
  final int unscheduledMinutes;
}

/// Earliest deadline first; difficulty breaks ties. Fixed events are hard constraints.
StudyPlan planStudy(
    {required List<Map<String, dynamic>> tasks,
    required List<BusySlot> busy,
    required DateTime now,
    int startHour = 18,
    int endHour = 22}) {
  final sorted = [...tasks]..sort((a, b) {
      final comparison =
          (a['deadline'] as String).compareTo(b['deadline'] as String);
      return comparison != 0
          ? comparison
          : (b['difficulty'] as int).compareTo(a['difficulty'] as int);
    });
  final occupied = [...busy];
  final blocks = <Map<String, dynamic>>[];
  int missing = 0;
  for (final task in sorted) {
    int remaining = task['remaining'] as int? ?? task['minutes'] as int;
    final deadline = DateTime.parse(task['deadline'] as String);
    for (int day = 0; day < 14 && remaining > 0; day++) {
      var cursor = DateTime(now.year, now.month, now.day + day, startHour);
      final endOfDay = DateTime(now.year, now.month, now.day + day, endHour);
      while (cursor.isBefore(endOfDay) && remaining > 0) {
        final duration = remaining > 50 ? 50 : remaining;
        final end = cursor.add(Duration(minutes: duration));
        if (!cursor.isBefore(now) &&
            !end.isAfter(deadline) &&
            !end.isAfter(endOfDay) &&
            !occupied.any((slot) => slot.overlaps(cursor, end))) {
          blocks.add({
            'id': '${task['id']}_${cursor.toIso8601String()}',
            'taskId': task['id'],
            'title': task['title'],
            'subject': task['subject'],
            'start': cursor.toIso8601String(),
            'end': end.toIso8601String()
          });
          occupied.add(BusySlot(cursor, end.add(const Duration(minutes: 10))));
          remaining -= duration;
          cursor = end.add(const Duration(minutes: 10));
        } else {
          cursor = cursor.add(const Duration(minutes: 5));
        }
      }
    }
    missing += remaining;
  }
  return StudyPlan(blocks, missing);
}
