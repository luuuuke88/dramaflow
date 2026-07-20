import 'package:dramaflow/src/util/storyboard_contact_sheet.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  Uint8List png(int width, int height, img.Color color) => Uint8List.fromList(
        img.encodePng(img.Image(width: width, height: height)..clear(color)),
      );

  test('完整导出过滤坏图、最多五列，并保留每列最大宽和每行最大高', () {
    final sheet = buildStoryboardContactSheet(
      [
        Uint8List.fromList([1, 2, 3]),
        png(20, 10, img.ColorRgb8(220, 20, 20)),
        png(10, 30, img.ColorRgb8(20, 220, 20)),
        png(15, 15, img.ColorRgb8(20, 20, 220)),
        png(5, 40, img.ColorRgb8(220, 220, 20)),
        png(25, 12, img.ColorRgb8(20, 220, 220)),
        png(50, 8, img.ColorRgb8(220, 20, 220)),
      ],
      mode: StoryboardContactSheetMode.export,
    );

    expect(sheet, isNotNull);
    expect(sheet!.imageCount, 6);
    expect(sheet.width, 105, reason: '第二行首列 50px 会按原版列宽规则扩展整列');
    expect(sheet.height, 48, reason: '首行最高 40，第二行只有 50x8 图片');
    final decoded = img.decodePng(sheet.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 105);
    expect(decoded.height, 48);
  });

  test('预览在布局前将每张图的宽度限制为 512，并编码 JPEG', () {
    final sheet = buildStoryboardContactSheet(
      [png(1024, 512, img.ColorRgb8(220, 20, 20))],
      mode: StoryboardContactSheetMode.preview,
    );

    expect(sheet, isNotNull);
    expect(sheet!.imageCount, 1);
    expect(sheet.width, 512);
    expect(sheet.height, 256);
    expect(sheet.mimeType, 'image/jpeg');
    expect(img.decodeJpg(sheet.bytes), isNotNull);
  });

  test('标签背景按 ToonFlow 的 fontSize 公式计算高度', () {
    final sheet = buildStoryboardContactSheet(
      [png(100, 100, img.ColorRgb8(255, 255, 255))],
      mode: StoryboardContactSheetMode.export,
    );

    final decoded = img.decodePng(sheet!.bytes)!;
    // 原版：fontSize=max(14, 100*.06)=14，padding=round(14*.4)=6，
    // 标签背景高=round(14)+6*2=26，从 y=4 覆盖到 y=29；y=30 已是白底。
    expect(decoded.getPixel(8, 29).r, lessThan(200));
    expect(decoded.getPixel(8, 30).r, 255);
  });

  test('没有可解码图片时不返回伪造的空画布', () {
    expect(
      buildStoryboardContactSheet(
        [
          Uint8List.fromList([0, 1, 2])
        ],
        mode: StoryboardContactSheetMode.export,
      ),
      isNull,
    );
  });

  test('预览合成器可在后台 isolate 返回可传递结果', () async {
    final sheet = await compute(
      buildStoryboardPreviewContactSheet,
      [png(8, 8, img.ColorRgb8(20, 220, 20))],
    );

    expect(sheet, isNotNull);
    expect(sheet!.imageCount, 1);
    expect(sheet.bytes, isNotEmpty);
    expect(img.decodeJpg(sheet.bytes), isNotNull);
  });

  test('完整 PNG 导出器可在后台 isolate 返回可传递结果', () async {
    final sheet = await compute(
      buildStoryboardExportContactSheet,
      [png(8, 8, img.ColorRgb8(20, 220, 20))],
    );

    expect(sheet, isNotNull);
    expect(sheet!.bytes, isNotEmpty);
    expect(img.decodePng(sheet.bytes), isNotNull);
  });
}
