import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 72,
    this.showWordmark = false,
    this.wordmark = 'Quản lý lịch học',
    this.subtitle,
  });

  final double size;
  final bool showWordmark;
  final String wordmark;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: const _GraduationCapCalendarPainter(),
        size: Size.square(size),
      ),
    );

    // Auth screens use stretch-aligned columns, so center the fixed-size mark
    // to keep the CustomPaint square instead of letting it fill the row width.
    if (!showWordmark) return Center(child: mark);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.22),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                wordmark,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: size * 0.27,
                  fontWeight: FontWeight.bold,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: size * 0.19,
                    color: AppPalette.textSecondary(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _GraduationCapCalendarPainter extends CustomPainter {
  const _GraduationCapCalendarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    const blue = Color(0xFF1688F8);
    const blueDark = Color(0xFF0867D7);
    const background = Color(0xFFCDE7F8);
    const shadow = Color(0xFF91C9E8);
    const cell = Color(0xFFC9C2C2);
    const brown = Color(0xFF5B3433);
    const white = Colors.white;

    final badge = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.5),
        width: w * 0.94,
        height: h * 0.94,
      ));
    canvas.drawPath(badge, Paint()..color = background);

    // Soft diagonal shadow keeps the flat calendar and cap badge readable.
    canvas.save();
    canvas.clipPath(badge);
    final shadowPath = Path()
      ..moveTo(w * 0.69, h * 0.23)
      ..lineTo(w * 0.96, h * 0.50)
      ..lineTo(w * 0.52, h * 0.97)
      ..lineTo(w * 0.27, h * 0.74)
      ..close();
    canvas.drawPath(shadowPath, Paint()..color = shadow);
    canvas.restore();

    // Calendar body and blue header.
    const calendarRadius = 0.055;
    final calendarRect = Rect.fromLTWH(w * 0.20, h * 0.25, w * 0.58, h * 0.52);
    canvas.drawRRect(
      RRect.fromRectAndRadius(calendarRect, Radius.circular(w * calendarRadius)),
      Paint()..color = white,
    );
    final headerRect = Rect.fromLTWH(w * 0.20, h * 0.25, w * 0.58, h * 0.19);
    canvas.drawRRect(
      RRect.fromRectAndRadius(headerRect, Radius.circular(w * 0.06)),
      Paint()..color = blue,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.20, h * 0.37, w * 0.58, h * 0.07),
      Paint()..color = blue,
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.20, h * 0.435, w * 0.58, h * 0.009),
      Paint()..color = blueDark,
    );

    // Calendar binding loops.
    for (final x in [0.27, 0.65]) {
      final loopRect = Rect.fromLTWH(w * x, h * 0.16, w * 0.075, h * 0.19);
      canvas.drawRRect(
        RRect.fromRectAndRadius(loopRect, Radius.circular(w * 0.025)),
        Paint()..color = background,
      );
      final ringRect = Rect.fromLTWH(w * (x + 0.009), h * 0.16, w * 0.057, h * 0.16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(ringRect, Radius.circular(w * 0.019)),
        Paint()..color = brown,
      );
    }

    // Three rows of calendar dates, with one blue highlighted day.
    for (var row = 0; row < 3; row++) {
      for (var column = 0; column < 3; column++) {
        final rect = Rect.fromLTWH(
          w * (0.28 + column * 0.115),
          h * (0.48 + row * 0.105),
          w * 0.088,
          h * 0.083,
        );
        final isHighlightedDay = row == 1 && column == 1;
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(w * 0.014)),
          Paint()..color = isHighlightedDay ? const Color(0xFF20B6DD) : cell,
        );
      }
    }

    // The lower-right badge carries the graduation cap mark.
    final badgeOuter = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.55, h * 0.51, w * 0.34, h * 0.34),
      Radius.circular(w * 0.075),
    );
    canvas.drawRRect(badgeOuter, Paint()..color = white);
    final badgeInner = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.565, h * 0.525, w * 0.31, h * 0.31),
      Radius.circular(w * 0.065),
    );
    canvas.drawRRect(badgeInner, Paint()..color = blue);

    final capBrim = Path()
      ..moveTo(w * 0.59, h * 0.67)
      ..lineTo(w * 0.72, h * 0.63)
      ..lineTo(w * 0.85, h * 0.67)
      ..lineTo(w * 0.72, h * 0.71)
      ..close();
    canvas.drawPath(capBrim, Paint()..color = white);

    final capBody = Path()
      ..moveTo(w * 0.65, h * 0.685)
      ..lineTo(w * 0.65, h * 0.715)
      ..quadraticBezierTo(w * 0.72, h * 0.75, w * 0.79, h * 0.715)
      ..lineTo(w * 0.79, h * 0.685)
      ..close();
    canvas.drawPath(capBody, Paint()..color = white);

    final capEdge = Paint()
      ..color = const Color(0xFF20B6DD)
      ..strokeWidth = w * 0.006
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.62, h * 0.68), Offset(w * 0.72, h * 0.712), capEdge);
    canvas.drawLine(Offset(w * 0.72, h * 0.712), Offset(w * 0.82, h * 0.68), capEdge);

    final tassel = Paint()
      ..color = white
      ..strokeWidth = w * 0.006
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.85, h * 0.67), Offset(w * 0.85, h * 0.705), tassel);
    canvas.drawCircle(Offset(w * 0.85, h * 0.71), w * 0.007, Paint()..color = white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AppLogoSmall extends StatelessWidget {
  const AppLogoSmall({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: const _GraduationCapCalendarPainter(),
        size: Size.square(size),
      ),
    );
  }
}

class AppGap extends StatelessWidget {
  const AppGap(this.height, {super.key});

  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: math.max(0, height));
}
