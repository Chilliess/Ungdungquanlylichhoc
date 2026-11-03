import 'package:flutter/material.dart';

/// Bảng màu dùng chung cho toàn bộ giao diện mới (đồng bộ với màu xanh
/// 0xFF4A90E2 đang dùng ở màn hình đăng nhập và trang chủ cũ).
class AppPalette {
  const AppPalette._();

  static const Color primary = Color(0xFF4A90E2);
  static const Color primaryDark = Color(0xFF2F6FD0);
  static const Color primaryLight = Color(0xFF7FB2F0);
  static const Color accent = Color(0xFFF2994A);
  static const Color success = Color(0xFF27AE60);
  static const Color danger = Color(0xFFEB5757);
  static const Color info = Color(0xFF56CCF2);
  static const Color warning = Color(0xFFF2994A);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF5AA0F2), Color(0xFF3A7BD5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const double radius = 20;
  static const double smallRadius = 14;

  static BorderRadius get cardRadius => BorderRadius.circular(radius);
  static BorderRadius get smallCardRadius => BorderRadius.circular(smallRadius);

  /// Nền chung của trang (ngoài nội dung thẻ).
  static Color background(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF141820)
          : const Color(0xFFF3F6FB);

  /// Nền thẻ (card) tương thích sáng/tối.
  static Color surface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E232B)
          : Colors.white;

  /// Nền phụ nhạt dùng cho các vùng "chip", khối thống kê nhỏ.
  static Color subtleSurface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF262C36)
          : const Color(0xFFF3F6FB);

  /// Viền mảnh cho card.
  static Color border(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.08)
          : const Color(0xFFE4EAF3);

  /// Màu chữ chính.
  static Color textPrimary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF1B2430);

  /// Màu chữ phụ.
  static Color textSecondary(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.65)
          : const Color(0xFF6B7A90);

  /// Đổ mã hex do người dùng chọn cho môn học thành Color.
  static Color fromHex(String? hex, {Color fallback = primary}) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }
}
