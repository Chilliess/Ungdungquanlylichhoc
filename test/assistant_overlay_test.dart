import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:untitled/services/app_preferences.dart';
import 'package:untitled/widgets/assistant_overlay.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appPreferences.showAssistant = true;
  });

  testWidgets(
      'chat survives minimise and navigation, but discards late replies on account change',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = StreamController<String?>();
    addTearDown(changes.close);
    final reply = Completer<String>();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        builder: (_, child) => AssistantOverlay(
            initialUserId: 'a',
            accountChanges: changes.stream,
            sendMessage: (_) => reply.future,
            child: child!),
        home: const Scaffold(body: Text('Home'))));
    await tester.tap(find.byTooltip('Mở trợ lý AI'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gửi đến Groq'), findsOneWidget);
    await tester.ensureVisible(find.text('Đồng ý và bắt đầu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đồng ý và bắt đầu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ôn thi thế nào?');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pump();
    await tester.tap(find.byTooltip('Thu gọn'));
    await tester.pump(const Duration(milliseconds: 400));
    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Settings'))));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Mở trợ lý AI'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ôn thi thế nào?'), findsOneWidget);
    changes.add('b');
    await tester.pump();
    reply.complete('Private answer for a');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mở trợ lý AI'));
    await tester.pumpAndSettle();
    expect(find.text('Private answer for a'), findsNothing);
    expect(find.text('Ôn thi thế nào?'), findsNothing);
    expect(find.text('Đồng ý và bắt đầu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small screen with keyboard fits and failed send restores draft',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final changes = StreamController<String?>();
    addTearDown(changes.close);
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(viewInsets: const EdgeInsets.only(bottom: 220)),
            child: AssistantOverlay(
                initialUserId: 'a',
                accountChanges: changes.stream,
                sendMessage: (_) async => throw StateError('offline'),
                child: child!)),
        home: const Scaffold()));
    await tester.tap(find.byTooltip('Mở trợ lý AI'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Đồng ý và bắt đầu'), 100,
        scrollable: find
            .descendant(
                of: find.byKey(const ValueKey('assistant-panel')),
                matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đồng ý và bắt đầu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bài tập');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Bài tập');
    expect(tester.takeException(), isNull);
  });

  testWidgets('server configuration error is visible and restores the draft', (tester) async {
    final changes = StreamController<String?>();
    addTearDown(changes.close);
    await tester.pumpWidget(MaterialApp(
        builder: (_, child) => AssistantOverlay(
            initialUserId: 'a', accountChanges: changes.stream,
            sendMessage: (_) async => throw const FunctionException(status: 503,
                details: {'error': 'Assistant not configured'}), child: child!),
        home: const Scaffold()));
    await tester.tap(find.byTooltip('Mở trợ lý AI'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Đồng ý và bắt đầu'));
    await tester.tap(find.text('Đồng ý và bắt đầu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hi');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pumpAndSettle();
    expect(find.text('Trợ lý chưa được cấu hình trên máy chủ.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'hi');
  });

  test('appearance migrates old theme and persists new preferences', () async {
    SharedPreferences.setMockInitialValues({'is_dark_mode': true});
    final prefs = AppPreferences();
    await prefs.load();
    expect(prefs.theme, ThemeMode.dark);
    await prefs.update(
        themeMode: ThemeMode.system,
        scale: 1.2,
        reduced: true,
        assistant: false);
    final reloaded = AppPreferences();
    await reloaded.load();
    expect(reloaded.theme, ThemeMode.system);
    expect(reloaded.textScale, 1.2);
    expect(reloaded.reduceMotion, isTrue);
    expect(reloaded.showAssistant, isFalse);
  });
}
