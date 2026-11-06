import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef WorkspaceTransport = Future<List<Map<String, dynamic>>> Function(
    String owner, String collection, List<Map<String, dynamic>> changes);

/// Durable per-item outbox. A refresh never treats unseen remote items as deleted.
class WorkspaceCollection {
  static String newId() {
    final random = Random.secure();
    return List.generate(
            16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  WorkspaceCollection(this.owner, this.collection,
      {WorkspaceTransport? transport, this.cacheNamespace = ''})
      : _transport = transport ?? _remote;
  final String owner, collection;
  final String cacheNamespace;
  final WorkspaceTransport _transport;
  List<Map<String, dynamic>> _items = [];
  Map<String, Map<String, dynamic>> _pending = {};
  bool _loaded = false;
  bool synced = false;
  Future<void> _queue = Future.value();
  String get _key => '${cacheNamespace}workspace_sync_v1:$owner:$collection';

  static Future<List<Map<String, dynamic>>> _remote(String owner,
      String collection, List<Map<String, dynamic>> changes) async {
    final client = Supabase.instance.client;
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    final rows = await client.rpc('sync_workspace_items', params: {
      'p_collection': collection,
      'p_changes': changes,
    }).timeout(const Duration(seconds: 12));
    if (client.auth.currentUser?.id != owner) {
      throw StateError('Account changed');
    }
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.catchError((Object _) {}).then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _cache() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
        _key,
        jsonEncode({
          'items': _items,
          'pending': _pending,
        }))) {
      throw StateError('Không lưu được dữ liệu trên thiết bị.');
    }
  }

  Future<void> _init(List<Map<String, dynamic>> legacy) async {
    if (_loaded) return;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw != null) {
      final data = jsonDecode(raw) as Map;
      _items = List<Map<String, dynamic>>.from(data['items'] as List);
      _pending = (data['pending'] as Map).map((key, value) =>
          MapEntry(key.toString(), Map<String, dynamic>.from(value as Map)));
    } else {
      _items = List<Map<String, dynamic>>.from(
          jsonDecode(jsonEncode(legacy)) as List);
      for (final item in _items) {
        final id = item['id'] as String;
        _pending[id] = {
          'id': id,
          'payload': item,
          'deleted': false,
          'overwrite': false
        };
      }
      await _cache();
    }
    _loaded = true;
  }

  Future<void> _flush() async {
    try {
      // Each batch commits independently; remaining entries stay in the outbox.
      do {
        final batch = _pending.values.take(100).toList();
        final rows = await _transport(owner, collection, batch);
        final beforeItems = _items;
        final beforePending = Map<String, Map<String, dynamic>>.from(_pending);
        for (final change in batch) {
          _pending.remove(change['id']);
        }
        final merged = <String, Map<String, dynamic>>{
          for (final row in rows)
            if (row['deleted'] != true)
              row['id'] as String:
                  Map<String, dynamic>.from(row['payload'] as Map),
        };
        for (final change in _pending.values) {
          if (change['deleted'] == true) {
            merged.remove(change['id']);
          } else {
            merged[change['id'] as String] =
                Map<String, dynamic>.from(change['payload'] as Map);
          }
        }
        _items = merged.values.toList();
        try {
          await _cache();
        } catch (_) {
          _items = beforeItems;
          _pending = beforePending;
          rethrow;
        }
      } while (_pending.isNotEmpty);
      synced = true;
    } catch (_) {
      // Local persistence succeeded; keep edits and deletions for a later retry.
      synced = false;
    }
  }

  List<Map<String, dynamic>> _copy() =>
      List<Map<String, dynamic>>.from(jsonDecode(jsonEncode(_items)) as List);

  Future<void> seed(List<Map<String, dynamic>> legacy) =>
      _serial(() => _init(legacy));

  Future<List<Map<String, dynamic>>> load(List<Map<String, dynamic>> legacy) =>
      _serial(() async {
        await _init(legacy);
        await _flush();
        return _copy();
      });

  Future<List<Map<String, dynamic>>> save(List<Map<String, dynamic>> items) {
    final snapshot =
        List<Map<String, dynamic>>.from(jsonDecode(jsonEncode(items)) as List);
    final baseline = _loaded ? _copy() : null;
    return _serial(() async {
      await _init([]);
      final previous = {
        for (final item in baseline ?? _items) item['id'] as String: item
      };
      final merged = {for (final item in _items) item['id'] as String: item};
      final incoming = {
        for (final item in snapshot) item['id'] as String: item
      };
      final oldPending = Map<String, Map<String, dynamic>>.from(_pending);
      final oldItems = _items;
      for (final item in snapshot) {
        final id = item['id'] as String;
        if (jsonEncode(previous[id]) != jsonEncode(item)) {
          _pending[id] = {
            'id': id,
            'payload': item,
            'deleted': false,
            'overwrite': true
          };
          merged[id] = item;
        }
      }
      for (final id in previous.keys.where((id) => !incoming.containsKey(id))) {
        _pending[id] = {
          'id': id,
          'payload': null,
          'deleted': true,
          'overwrite': true
        };
        merged.remove(id);
      }
      _items = merged.values.toList();
      try {
        await _cache();
      } catch (_) {
        _items = oldItems;
        _pending = oldPending;
        rethrow;
      }
      await _flush();
      return _copy();
    });
  }
}
