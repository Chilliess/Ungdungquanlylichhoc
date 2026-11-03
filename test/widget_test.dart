// Widget test cho ứng dụng quản lý lịch học.
//
// Lưu ý: test này KHÔNG gọi `Supabase.initialize()` (giống môi trường test mặc
// định), nên đây cũng là hồi quy cho lỗi trước đây: `Splashscreen` truy cập
// `Supabase.instance.client` ngay trong field initializer khiến ứng dụng ném
// `AssertionError: You must initialize the supabase instance before calling
// Supabase.instance` ngay khi khởi động.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:untitled/main.dart';
import 'package:untitled/splash/splashscreen.dart';

void main() {
  testWidgets('Splash hiển thị logo và không lỗi khi chưa khởi tạo Supabase',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Màn splash đã dựng được mà không ném lỗi khởi tạo Supabase.
    expect(tester.takeException(), isNull);
    expect(find.byType(Splashscreen), findsOneWidget);
    expect(find.byType(FlutterLogo), findsOneWidget);

    // Chờ hết timer chuyển màn (3 giây) để không còn timer pending.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Splash tự chuyển sang màn đăng nhập khi chưa có phiên đăng nhập',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    // Chưa đăng nhập -> sau 3 giây sẽ tới Loginscreen.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Đăng nhập'), findsWidgets);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
  });

  testWidgets('Màn đăng nhập có nút đăng nhập và liên kết đăng ký',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.text('Quên mật khẩu?'), findsOneWidget);
    expect(find.text('Đăng ký'), findsOneWidget);
  });
}
