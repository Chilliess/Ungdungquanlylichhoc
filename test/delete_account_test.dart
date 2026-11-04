import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/screen/delete_account_screen.dart';
import 'package:untitled/screen/settings.dart';
import 'package:untitled/services/account_lifecycle.dart';
import 'package:untitled/widgets/account_gate.dart';

class FakeLifecycle extends AccountLifecycle {
  Map<String, dynamic> result = {
    'status': 'pending',
    'delete_at': '2026-11-11T12:00:00Z'
  };
  int restores = 0, signOuts = 0;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> status() async {
    if (fail) throw StateError('offline');
    return result;
  }

  @override
  Future<Map<String, dynamic>> restore() async {
    restores++;
    result = {'status': 'active'};
    return result;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:54321', anonKey: 'test');
  });
  testWidgets(
      'agreement and exact delete required; request records server deadline',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    var left = false;
    await tester.pumpWidget(MaterialApp(
        home: DeleteAccountScreen(onRequested: () async {
      left = true;
    }, request: (body) async {
      calls.add(body);
      return {'status': 'pending', 'delete_at': '2026-11-11T12:00:00Z'};
    })));
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('request-deletion'));
    for (final invalid in ['DELETE', 'delete ', '']) {
      await tester.enterText(find.byType(TextField), invalid);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
    }
    expect(calls, isEmpty);
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(calls, [
      {'action': 'request', 'confirmation': 'delete'}
    ]);
    expect(left, true);
    expect(find.text('Đã yêu cầu xóa tài khoản'), findsOneWidget);
  });
  testWidgets('request error never claims deletion or signs out',
      (tester) async {
    var left = false;
    await tester.pumpWidget(MaterialApp(
        home: DeleteAccountScreen(
            onRequested: () async {
              left = true;
            },
            request: (_) async => throw StateError('offline'))));
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('request-deletion')));
    await tester.pumpAndSettle();
    expect(left, false);
    expect(find.textContaining('Chưa gửi được yêu cầu'), findsOneWidget);
  });
  testWidgets('pending login stays blocked until explicit restoration',
      (tester) async {
    final service = FakeLifecycle();
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => AccountGate(
            lifecycle: service,
            initialUserId: 'a',
            accountChanges: const Stream.empty(),
            child: child!),
        home: const Scaffold(body: Text('Private app'))));
    await tester.pumpAndSettle();
    expect(find.text('Private app'), findsNothing);
    expect(service.restores, 0);
    await tester.tap(find.text('Không khôi phục · Đăng xuất'));
    await tester.pumpAndSettle();
    expect(service.signOuts, 1);
    expect(service.restores, 0);
    expect(find.text('Private app'), findsNothing);
    await tester.tap(find.text('Khôi phục tài khoản'));
    await tester.pumpAndSettle();
    expect(service.restores, 1);
    expect(find.text('Private app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'expired account cannot restore; status failure never reveals app',
      (tester) async {
    final service = FakeLifecycle()..result = {'status': 'expired'};
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => AccountGate(
            lifecycle: service,
            initialUserId: 'a',
            accountChanges: const Stream.empty(),
            child: child!),
        home: const Scaffold(body: Text('Private app'))));
    await tester.pumpAndSettle();
    expect(find.text('Khôi phục tài khoản'), findsNothing);
    expect(find.text('Private app'), findsNothing);
    service.fail = true;
    accountStatusRefresh.value++;
    await tester.pumpAndSettle();
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Private app'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('settings fit narrow screen with large text', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
