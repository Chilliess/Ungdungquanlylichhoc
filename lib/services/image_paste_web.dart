// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

Stream<Uint8List> pastedImages() async* {
  await for (final event in html.document.onPaste) {
    final files = event.clipboardData?.files;
    if (files == null || files.isEmpty) continue;
    final file = files.first;
    if (!file.type.startsWith('image/')) continue;
    event.preventDefault();
    if (file.size > 3 * 1024 * 1024) {
      yield Uint8List(0);
      continue;
    }
    final reader = html.FileReader()..readAsArrayBuffer(file);
    await reader.onLoad.first;
    final result = reader.result;
    if (result is ByteBuffer) yield result.asUint8List();
    if (result is Uint8List) yield result;
  }
}
