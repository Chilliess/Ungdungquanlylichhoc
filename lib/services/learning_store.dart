import 'dart:convert';
import 'workspace_sync.dart';
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
  static String id() => WorkspaceCollection.newId();
  int _savedGoal = 600;

  final Map<String, WorkspaceCollection> _collections = {};
  List<Map<String, dynamic>> subjects = [];
  bool get cloudSynced =>
      _collections.isNotEmpty && _collections.values.every((c) => c.synced);
  String subjectName(Map<String, dynamic> task) {
    final matches = subjects.where((s) => s['id'] == task['subjectId']);
    return matches.isNotEmpty
        ? matches.first['subject_name'].toString()
        : (task['subject']?.toString().isNotEmpty == true
            ? task['subject'].toString()
            : 'Cá nhân');
  }

  Future<void>? _loading;
  String? _loadingOwner;
  int _generation = 0;
  Future<void> load() async {
    final owner = Supabase.instance.client.auth.currentUser?.id;
    if (_loading != null && _loadingOwner == owner) return _loading!;
    final pending = _load();
    _loadingOwner = owner;
    _loading = pending;
    try {
      await pending;
    } finally {
      if (identical(_loading, pending)) _loading = null;
    }
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final owner = client.auth.currentUser?.id;
    if (_loaded && owner == _owner) return;
    final generation = ++_generation;
    _owner = owner;
    _loaded = false;
    _collections.clear();
    tasks = [];
    blocks = [];
    logs = [];
    subjects = [];
    goalMinutes = 600;
    if (owner == null) {
      notifyListeners();
      return;
    }
    final raw = (await SharedPreferences.getInstance()).getString(key(owner));
    if (generation != _generation || _owner != owner) return;
    if (raw != null) {
      final data = jsonDecode(raw) as Map;
      tasks = List<Map<String, dynamic>>.from(data['tasks'] as List);
      blocks = List<Map<String, dynamic>>.from(data['blocks'] as List);
      logs = List<Map<String, dynamic>>.from(data['logs'] as List);
      goalMinutes = data['goal'] as int? ?? 600;
    }
    final seeds = <String, List<Map<String, dynamic>>>{
      'tasks': tasks, 'blocks': blocks, 'logs': logs,
      // An untouched default must not overwrite a goal from another device.
      'settings': raw == null
          ? []
          : [
              {'id': 'goal', 'minutes': goalMinutes}
            ],
    };
    final collections = {
      for (final name in seeds.keys) name: WorkspaceCollection(owner, name)
    };
    final results = await Future.wait(seeds.entries
        .map((entry) => collections[entry.key]!.load(entry.value)));
    if (generation != _generation ||
        _owner != owner ||
        client.auth.currentUser?.id != owner) {
      return;
    }
    _collections.addAll(collections);
    tasks = results[0];
    blocks = results[1];
    logs = results[2];
    if (results[3].isNotEmpty) {
      goalMinutes = results[3].first['minutes'] as int? ?? 600;
    }
    try {
      final rows = await client
          .from('subjects')
          .select('id,subject_name,subject_code')
          .eq('user_id', owner)
          .order('subject_name');
      if (generation != _generation ||
          _owner != owner ||
          client.auth.currentUser?.id != owner) {
        return;
      }
      subjects = List<Map<String, dynamic>>.from(rows);
    } catch (_) {/* Tasks remain usable from the device cache. */}
    if (generation != _generation ||
        _owner != owner ||
        client.auth.currentUser?.id != owner) {
      return;
    }
    _loaded = true;
    _savedGoal = goalMinutes;
    await _cache(owner);
    notifyListeners();
  }

  Future<void> _cache(String owner) async {
    final encoded = jsonEncode(
        {'tasks': tasks, 'blocks': blocks, 'logs': logs, 'goal': goalMinutes});
    if (!await (await SharedPreferences.getInstance())
        .setString(key(owner), encoded)) {
      throw StateError('Không lưu được dữ liệu trên thiết bị.');
    }
  }

  Future<void> refresh() async {
    await _writes.catchError((Object _) {});
    _loaded = false;
    await load();
  }

  Future<void> save() async {
    final owner = _owner, generation = _generation;
    if (!_loaded ||
        owner == null ||
        owner != Supabase.instance.client.auth.currentUser?.id) {
      throw StateError('Vui lòng đăng nhập lại.');
    }
    final snapshot = jsonDecode(jsonEncode([
      tasks,
      blocks,
      logs,
      [
        {'id': 'goal', 'minutes': goalMinutes}
      ]
    ])) as List;
    final goalChanged = goalMinutes != _savedGoal;
    final collections = Map<String, WorkspaceCollection>.from(_collections);
    _writes = _writes.catchError((_) {}).then((_) async {
      if (Supabase.instance.client.auth.currentUser?.id != owner) {
        throw StateError('Account changed');
      }
      final names = ['tasks', 'blocks', 'logs', 'settings'];
      final results = await Future.wait(List.generate(
          4,
          (i) => i == 3 && !goalChanged
              ? collections['settings']!.load([])
              : collections[names[i]]!
                  .save(List<Map<String, dynamic>>.from(snapshot[i] as List))));
      if (generation != _generation ||
          _owner != owner ||
          Supabase.instance.client.auth.currentUser?.id != owner) {
        return;
      }
      tasks = results[0];
      blocks = results[1];
      logs = results[2];
      if (results[3].isNotEmpty) {
        goalMinutes = results[3].first['minutes'] as int? ?? 600;
      }
      await _cache(owner);
      _savedGoal = goalMinutes;
      notifyListeners();
    });
    await _writes;
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
            'subjectId': task['subjectId'],
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
