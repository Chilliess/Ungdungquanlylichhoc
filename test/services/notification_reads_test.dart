import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/services/notification_reads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('read state survives reload and is isolated by account and occurrence',
      () async {
    final reads = NotificationReads();
    final key =
        NotificationReads.key('schedule', 'one', DateTime(2026, 11, 6, 9));
    await reads.mark('a', [key]);
    final reloaded = NotificationReads();
    await Future.wait([reloaded.load('a'), reloaded.load('b')]);
    expect(reloaded.isRead('a', key), isTrue);
    expect(reloaded.isRead('b', key), isFalse);
    expect(
        reloaded.isRead('a',
            NotificationReads.key('schedule', 'one', DateTime(2026, 11, 7, 9))),
        isFalse);
    expect(reloaded.isRead(null, key), isFalse);
  });
  test('concurrent marks do not overwrite other read items', () async {
    final reads = NotificationReads();
    await Future.wait([
      reads.mark('a', ['one']),
      reads.mark('a', ['two'])
    ]);
    final reloaded = NotificationReads();
    await reloaded.load('a');
    expect(reloaded.isRead('a', 'one'), isTrue);
    expect(reloaded.isRead('a', 'two'), isTrue);
  });
}
