import 'dart:io';
import 'dart:typed_data';

import 'package:dramaflow/src/screens/production/workbench_preview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('writeWorkbenchPreviewZip 原样写入 ZIP 字节', () async {
    final dir = Directory.systemTemp.createTempSync('dramaflow-preview-export-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = p.join(dir.path, 'preview.zip');
    final bytes = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 1, 2, 3]);

    await writeWorkbenchPreviewZip(bytes, target);

    expect(File(target).readAsBytesSync(), bytes);
  });
}
