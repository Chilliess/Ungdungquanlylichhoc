import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/services/workspace_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, Map<String, Map<String, dynamic>>> server;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    server = {};
  });
  Future<List<Map<String, dynamic>>> remote(String owner, String collection,
      List<Map<String, dynamic>> changes) async {
    final rows = server.putIfAbsent('$owner:$collection', () => {});
    for (final change in changes) {
      final id = change['id'] as String;
      if (!rows.containsKey(id) || change['overwrite'] == true) {
        rows[id] =
            Map<String, dynamic>.from(jsonDecode(jsonEncode(change)) as Map);
      }
    }
    return List<Map<String, dynamic>>.from(
        jsonDecode(jsonEncode(rows.values.toList())) as List);
  }

  Map<String, dynamic> task(String id, String title) =>
      {'id': id, 'title': title};
  WorkspaceCollection device(String name,
          {String owner = 'user',
          String collection = 'tasks',
          WorkspaceTransport? transport}) =>
      WorkspaceCollection(owner, collection,
          cacheNamespace: name, transport: transport ?? remote);

  test('two devices merge different items without deleting unseen remote work',
      () async {
    final a = device('a'), b = device('b');
    await a.load([]);
    await b.load([]);
    await a.save([task('one', 'A')]);
    final merged = await b.save([task('two', 'B')]);
    expect(merged.map((t) => t['id']).toSet(), {'one', 'two'});
    expect((await a.load([])).length, 2);
    final edited = await a.save([task('one', 'edited'), task('two', 'B')]);
    expect(edited.singleWhere((t) => t['id'] == 'one')['title'], 'edited');
  });

  test(
      'offline deletion survives restart and old migration cannot resurrect it',
      () async {
    var online = true;
    Future<List<Map<String, dynamic>>> transport(String owner,
        String collection, List<Map<String, dynamic>> changes) async {
      if (!online) throw StateError('offline');
      return remote(owner, collection, changes);
    }

    final a = device('a', transport: transport);
    await a.load([task('one', 'original')]);
    online = false;
    expect(await a.save([]), isEmpty);
    expect(a.synced, isFalse);
    final restarted = device('a', transport: transport);
    expect(await restarted.load([]), isEmpty);
    online = true;
    expect(await restarted.load([]), isEmpty);
    expect(restarted.synced, isTrue);
    final oldDevice = device('old');
    expect(await oldDevice.load([task('one', 'stale backup')]), isEmpty);
  });

  test('offline edits persist and retry; account and collection are isolated',
      () async {
    final offline = device('a',
        transport: (_, __, ___) async => throw StateError('offline'));
    await offline.load([]);
    await offline.save([task('one', 'saved offline')]);
    final restarted = device('a');
    expect((await restarted.load([])).single['title'], 'saved offline');
    expect(await device('other', owner: 'other').load([]), isEmpty);
    expect(await device('chat', collection: 'chat').load([]), isEmpty);
    expect(restarted.synced, isTrue);
  });

  test('migration on a second device preserves the newer cloud version',
      () async {
    final a = device('a');
    await a.load([]);
    await a.save([task('one', 'new version')]);
    expect(
        (await device('old').load([task('one', 'old version')]))
            .single['title'],
        'new version');
  });

  test('queued saves retain new remote items not seen by the caller', () async {
    final a = device('a');
    await a.load([]);
    final first = a.save([task('one', 'first')]);
    final second = a.save([task('one', 'second'), task('two', 'second item')]);
    await Future.wait([first, second]);
    final rows = await device('b').load([]);
    expect(rows.length, 2);
    expect(rows.singleWhere((t) => t['id'] == 'one')['title'], 'second');
  });
}
