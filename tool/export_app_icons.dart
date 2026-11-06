// Run: flutter test tool/export_app_icons.dart
// Render the existing project mark for every supported platform.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/widgets/app_logo.dart';

Future<void> writeBytes(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

void main() {
  testWidgets('Export project branding for web, Android and Windows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey();
    await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
            child: RepaintBoundary(
                key: key, child: const AppLogoSmall(size: 1024)))));
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final normal = <int, Uint8List>{};
      Future<Uint8List> png(int size,
          {double inset = 0, bool background = false}) async {
        if (inset == 0 && normal.containsKey(size)) return normal[size]!;
        final mark = await boundary.toImage(pixelRatio: size / 1024);
        ui.Image output = mark;
        if (inset > 0) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          if (background) {
            canvas.drawColor(const Color(0xFFF5F6FB), BlendMode.src);
          }
          final side = size.toDouble();
          canvas.drawImageRect(
              mark,
              Rect.fromLTWH(0, 0, side, side),
              Rect.fromLTWH(side * inset, side * inset, side * (1 - inset * 2),
                  side * (1 - inset * 2)),
              Paint()..filterQuality = FilterQuality.high);
          final picture = recorder.endRecording();
          output = await picture.toImage(size, size);
          picture.dispose();
        }
        final bytes =
            (await output.toByteData(format: ui.ImageByteFormat.png))!;
        final result =
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
        if (inset > 0) output.dispose();
        mark.dispose();
        if (inset == 0) normal[size] = result;
        return result;
      }

      await writeBytes('assets/branding/project_logo.png', await png(1024));
      await writeBytes('web/favicon.png', await png(48));
      await writeBytes('web/icons/apple-touch-icon.png',
          await png(180, inset: .15, background: true));
      for (final size in [192, 512]) {
        await writeBytes('web/icons/Icon-$size.png', await png(size));
        await writeBytes('web/icons/Icon-maskable-$size.png',
            await png(size, inset: .15, background: true));
      }
      for (final density in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192
      }.entries) {
        await writeBytes(
            'android/app/src/main/res/mipmap-${density.key}/ic_launcher.png',
            await png(density.value));
      }
      await writeBytes(
          'android/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png',
          await png(432, inset: .15));
      const sizes = [16, 24, 32, 48, 64, 128, 256];
      final frames = <Uint8List>[];
      for (final size in sizes) {
        frames.add(await png(size));
      }
      final header = ByteData(6 + 16 * sizes.length);
      header.setUint16(2, 1, Endian.little);
      header.setUint16(4, sizes.length, Endian.little);
      var offset = header.lengthInBytes;
      for (var i = 0; i < sizes.length; i++) {
        final entry = 6 + i * 16;
        header.setUint8(entry, sizes[i] % 256);
        header.setUint8(entry + 1, sizes[i] % 256);
        header.setUint16(entry + 4, 1, Endian.little);
        header.setUint16(entry + 6, 32, Endian.little);
        header.setUint32(entry + 8, frames[i].length, Endian.little);
        header.setUint32(entry + 12, offset, Endian.little);
        offset += frames[i].length;
      }
      final icon = BytesBuilder()..add(header.buffer.asUint8List());
      for (final frame in frames) {
        icon.add(frame);
      }
      await writeBytes(
          'windows/runner/resources/app_icon.ico', icon.takeBytes());
      await writeBytes('build/icon_preview/app_icon.png', await png(256));
      await writeBytes('build/icon_preview/maskable.png',
          await png(256, inset: .15, background: true));
    });
  });
}
