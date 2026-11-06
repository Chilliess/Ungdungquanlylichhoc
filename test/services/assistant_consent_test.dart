import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:untitled/services/assistant_consent.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('refresh and new browser restore consent from the account', () async {
    final accepted = <String>{};
    AssistantConsent store() => AssistantConsent(
        readAccount: (owner) async => accepted.contains(owner),
        acceptAccount: (owner) async {
          accepted.add(owner);
        });
    expect(await store().load('a'), isFalse);
    await store().accept('a');
    expect(await store().load('a'), isTrue);
    SharedPreferences.setMockInitialValues({});
    expect(await store().load('a'), isTrue);
    expect(await store().load('b'), isFalse);
  });

  test('previous explicit local acceptance migrates without another click',
      () async {
    SharedPreferences.setMockInitialValues({AssistantConsent.key('a'): true});
    String? migrated;
    final store = AssistantConsent(
        readAccount: (_) async => false,
        acceptAccount: (owner) async {
          migrated = owner;
        });
    expect(await store.load('a'), isTrue);
    expect(migrated, 'a');
    expect(await store.load('b'), isFalse);
    expect(migrated, 'a');
  });

  test('failed account save does not falsely record permanent acceptance',
      () async {
    final store = AssistantConsent(
        acceptAccount: (_) async => throw StateError('offline'));
    await expectLater(store.accept('a'), throwsStateError);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AssistantConsent.key('a')), isNull);
  });

  test('network failure uses only the matching account cache', () async {
    SharedPreferences.setMockInitialValues({AssistantConsent.key('a'): true});
    final store =
        AssistantConsent(readAccount: (_) async => throw StateError('offline'));
    expect(await store.load('a'), isTrue);
    await expectLater(store.load('b'), throwsStateError);
  });
}
