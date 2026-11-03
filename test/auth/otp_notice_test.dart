import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/auth/forgot_password_screen.dart';
import 'package:untitled/widgets/app_notice.dart';

void main() {
  testWidgets('OTP disables resend for 60 seconds and restarts after resend',
      (tester) async {
    var now = DateTime(2026, 11, 3);
    var sends = 0;
    await tester.pumpWidget(MaterialApp(
        home: ForgotPasswordScreen(
      initialEmail: 'test@example.com',
      currentTime: () => now,
      sendRecoveryCode: (_) async {
        sends++;
      },
    )));
    await tester.tap(find.text('Gửi mã OTP'));
    await tester.pumpAndSettle();
    expect(sends, 1);
    expect(find.text('Vui lòng thử lại sau 60 giây'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Vui lòng thử lại sau 60 giây'))
            .onPressed,
        isNull);
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Vui lòng thử lại sau 59 giây'), findsOneWidget);
    now = now.add(const Duration(seconds: 59));
    await tester.pump(const Duration(seconds: 59));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Gửi lại mã'))
            .onPressed,
        isNotNull);
    await tester.tap(find.text('Gửi lại mã'));
    await tester.pumpAndSettle();
    expect(sends, 2);
    expect(find.text('Vui lòng thử lại sau 60 giây'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('notices slide from top, replace previous and dismiss',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const Scaffold(body: Text('Page'));
    })));
    AppNotice.show(
        context, const SnackBar(content: Text('Thông báo thứ nhất')));
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.text('Thông báo thứ nhất')).dy, lessThan(100));
    expect(find.byType(SnackBar), findsNothing);
    AppNotice.show(context, const SnackBar(content: Text('Thông báo mới')));
    await tester.pumpAndSettle();
    expect(find.text('Thông báo thứ nhất'), findsNothing);
    await tester.tap(find.byTooltip('Đóng thông báo'));
    await tester.pumpAndSettle();
    expect(find.text('Thông báo mới'), findsNothing);
    AppNotice.show(context, const SnackBar(content: Text('Tự ẩn')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Tự ẩn'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
