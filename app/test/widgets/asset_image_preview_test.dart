import 'dart:io';
import 'dart:typed_data';

import 'package:dramaflow/l10n/app_localizations.dart';
import 'package:dramaflow/src/widgets/asset_image_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('剪贴板图片统一编码为 PNG', () {
    final jpegBytes = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 1, height: 1)),
    );

    final clipboardBytes = imageBytesForClipboard(jpegBytes);

    expect(img.decodePng(clipboardBytes), isNotNull);
  });

  testWidgets('本地图片预览调用共享复制与另存动作', (tester) async {
    final directory = Directory.systemTemp.createTempSync('dramaflow-preview-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final pngBytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 1, height: 1)),
    );
    final image = File('${directory.path}/portrait.png')
      ..writeAsBytesSync(pngBytes);
    Uint8List? copied;
    String? saved;
    String? readPath;

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
      locale: const Locale('zh'),
      home: AssetImagePreviewPage(
        absPath: image.path,
        actions: ImagePreviewActions(
          readImageBytes: (path) {
            readPath = path;
            return Future.value(pngBytes);
          },
          copyImageBytes: (bytes) {
            copied = bytes;
            return Future.value();
          },
          saveImage: (path) {
            saved = path;
            return Future.value();
          },
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('asset-image-copy')));
    // _copy now runs imageBytesForClipboard through compute() on a real
    // background isolate; runAsync lets that isolate round-trip actually
    // complete before we pump and assert (a bare pump() isn't enough).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(readPath, image.path);
    expect(copied, isNotNull);
    expect(copied, orderedEquals(pngBytes));

    await tester.tap(find.byKey(const ValueKey('asset-image-save')));
    await tester.pump();
    expect(saved, image.path);
  });
}
