import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:untitled/auth/widgets/brand_icon.dart';
import 'package:untitled/auth/widgets/social_auth_button.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: child),
    ),
  );
}

void main() {
  group('BrandIcon', () {
    testWidgets('Google dùng icon Font Awesome brand, không dùng chữ cái',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const BrandIcon(provider: AuthProvider.google)),
      );

      final faIcon = tester.widget<FaIcon>(find.byType(FaIcon));
      expect(faIcon.icon, FontAwesomeIcons.google.data);
      expect(find.text('G'), findsNothing);
    });

    testWidgets('Microsoft dùng icon Font Awesome brand',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const BrandIcon(provider: AuthProvider.microsoft)),
      );

      final faIcon = tester.widget<FaIcon>(find.byType(FaIcon));
      expect(faIcon.icon, FontAwesomeIcons.microsoft.data);
      expect(find.text('M'), findsNothing);
    });

    testWidgets('Các icon dùng font family FontAwesomeBrands',
        (WidgetTester tester) async {
      for (final provider in AuthProvider.values) {
        await tester.pumpWidget(_wrap(BrandIcon(provider: provider)));
        final faIcon = tester.widget<FaIcon>(find.byType(FaIcon));
        expect(faIcon.icon?.fontFamily, 'FontAwesomeBrands');
        expect(faIcon.icon?.fontPackage, 'font_awesome_flutter');
      }
    });

    testWidgets('Google được phủ gradient 4 màu qua ShaderMask',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(const BrandIcon(provider: AuthProvider.google)),
      );

      expect(find.byType(ShaderMask), findsOneWidget);

      final shaderMask = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(shaderMask.blendMode, BlendMode.srcIn);

      // Gradient phải dùng đúng 4 màu thương hiệu của Google.
      expect(BrandIcon.googleGradient.colors.length, 4);
      expect(BrandIcon.googleGradient.colors[0], const Color(0xFF4285F4));
      expect(BrandIcon.googleGradient.colors[1], const Color(0xFFEA4335));
      expect(BrandIcon.googleGradient.colors[2], const Color(0xFFFBBC05));
      expect(BrandIcon.googleGradient.colors[3], const Color(0xFF34A853));

      // shaderCallback phải tạo shader từ đúng gradient đó.
      final shader =
          shaderMask.shaderCallback(const Rect.fromLTWH(0, 0, 20, 20));
      expect(shader, isNotNull);
    });
  });

  group('SocialAuthButton', () {
    testWidgets('Hiển thị icon thương hiệu kèm nhãn',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(
          Row(
            children: [
              SocialAuthButton(
                provider: AuthProvider.google,
                label: 'Google',
                onPressed: () {},
              ),
            ],
          ),
        ),
      );

      expect(find.byType(BrandIcon), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
    });

    testWidgets('Gọi onPressed khi nhấn', (WidgetTester tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          Row(
            children: [
              SocialAuthButton(
                provider: AuthProvider.microsoft,
                label: 'Microsoft',
                onPressed: () => tapped = true,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byType(OutlinedButton));
      expect(tapped, isTrue);
    });
  });
}
