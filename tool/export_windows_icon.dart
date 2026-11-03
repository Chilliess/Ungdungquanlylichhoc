// Run with: flutter test tool/export_windows_icon.dart
// Render the existing app logo directly, then pack PNG frames into a Windows ICO.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:untitled/widgets/app_logo.dart';

void main() {
  testWidgets('Export Windows icon from AppLogoSmall', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: key,
          child: const AppLogoSmall(size: 256),
        ),
      ),
    ));
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    const sizes = [16, 24, 32, 48, 64, 128, 256];
    final frames = <Uint8List>[];
    await tester.runAsync(() async {
      for (final size in sizes) {
        final image = await boundary.toImage(pixelRatio: size / 256);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        frames.add(bytes!.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
        image.dispose();
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
      await File('windows/runner/resources/app_icon.ico').writeAsBytes(icon.takeBytes());
      await Directory('build/icon_preview').create(recursive: true);
      await File('build/icon_preview/app_icon.png').writeAsBytes(frames.last);
    });
  });
}
