import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Các nhà cung cấp đăng nhập qua mạng xã hội được hỗ trợ trong giao diện.
enum AuthProvider {
  google,
  microsoft,
}

/// Nhãn hiển thị của từng nhà cung cấp.
extension AuthProviderLabel on AuthProvider {
  String get label {
    switch (this) {
      case AuthProvider.google:
        return 'Google';
      case AuthProvider.microsoft:
        return 'Microsoft';
    }
  }
}

/// Biểu tượng thương hiệu của nhà cung cấp (Google / Microsoft).
///
/// Dùng `FaIcon` thay cho `Icon` vì icon Font Awesome không vuông, nếu dùng
/// `Icon` chuẩn sẽ bị cắt/mis-align.
class BrandIcon extends StatelessWidget {
  const BrandIcon({
    super.key,
    required this.provider,
    this.size = 20,
  });

  final AuthProvider provider;
  final double size;

  // Bảng màu chính thức của từng thương hiệu.
  static const Color _googleBlue = Color(0xFF4285F4);
  static const Color _googleRed = Color(0xFFEA4335);
  static const Color _googleYellow = Color(0xFFFBBC05);
  static const Color _googleGreen = Color(0xFF34A853);
  static const Color _microsoftBlue = Color(0xFF00A4EF);

  /// Gradient 4 màu của logo Google (xanh → đỏ → vàng → xanh lá).
  static const LinearGradient googleGradient = LinearGradient(
    colors: [
      _googleBlue,
      _googleRed,
      _googleYellow,
      _googleGreen,
    ],
    stops: [0.0, 0.45, 0.72, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    switch (provider) {
      case AuthProvider.google:
        // Chữ "G" nhiều màu: dùng ShaderMask để phủ gradient lên glyph.
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => googleGradient.createShader(bounds),
          child: FaIcon(FontAwesomeIcons.google, size: size),
        );

      case AuthProvider.microsoft:
        return FaIcon(
          FontAwesomeIcons.microsoft,
          size: size,
          color: _microsoftBlue,
        );

    }
  }
}
