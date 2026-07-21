import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// ToonFlow 分镜预览的两种输出：页内预览用缩略 JPEG，导出用原尺寸 PNG。
enum StoryboardContactSheetMode { preview, export }

/// 已编码的分镜联系表，以及构图后可用于 UI 的尺寸和有效图数。
class StoryboardContactSheet {
  final Uint8List bytes;
  final int width;
  final int height;
  final int imageCount;
  final String mimeType;

  const StoryboardContactSheet({
    required this.bytes,
    required this.width,
    required this.height,
    required this.imageCount,
    required this.mimeType,
  });
}

/// 按 ToonFlow `previewImage` / `downPreviewImage` 的规则合成首帧联系表。
///
/// 无效图片会被跳过；有效图片保留传入顺序、每行最多五列。预览模式在布局前
/// 把每张图片的宽度限制为 512px；完整导出保留更多细节，但同样有上限
/// （[_exportMaxWidth]），避免个别超大源图（比如模型直出的高分辨率图）在
/// 拼接多张图时把内存占用推到不可控的量级。标签序号使用调用方传入的
/// `shotNumber`（应为该分镜在完整分镜列表里的真实序号），不是过滤掉未生成
/// 分镜之后、在这个子集里重新计数的下标——否则联系表标签会跟画布网格编号
/// 错位，指错分镜。
StoryboardContactSheet? buildStoryboardContactSheet(
  Iterable<({int shotNumber, Uint8List bytes})> sources, {
  required StoryboardContactSheetMode mode,
}) {
  final maxWidth = mode == StoryboardContactSheetMode.preview
      ? _previewMaxWidth
      : _exportMaxWidth;
  final images = <({int shotNumber, img.Image image})>[];
  for (final source in sources) {
    try {
      final decoded = img.decodeImage(source.bytes);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        continue;
      }
      images.add((
        shotNumber: source.shotNumber,
        image: decoded.width > maxWidth
            ? img.copyResize(decoded, width: maxWidth)
            : decoded,
      ));
    } catch (_) {
      // ToonFlow 同样过滤读取或解析失败的文件，不生成伪造空预览。
    }
  }
  if (images.isEmpty) return null;

  final columns = images.length < _maxColumns ? images.length : _maxColumns;
  final rows = (images.length / columns).ceil();
  final columnWidths = List<int>.filled(columns, 0);
  final rowHeights = List<int>.filled(rows, 0);
  for (final (index, entry) in images.indexed) {
    final column = index % columns;
    final row = index ~/ columns;
    if (entry.image.width > columnWidths[column]) {
      columnWidths[column] = entry.image.width;
    }
    if (entry.image.height > rowHeights[row]) {
      rowHeights[row] = entry.image.height;
    }
  }

  final width = columnWidths.fold(0, (sum, item) => sum + item);
  final height = rowHeights.fold(0, (sum, item) => sum + item);
  final canvas = img.Image(width: width, height: height)
    ..clear(img.ColorRgba8(255, 255, 255, 255));

  for (final (index, entry) in images.indexed) {
    final column = index % columns;
    final row = index ~/ columns;
    final left = columnWidths.take(column).fold(0, (sum, item) => sum + item);
    final top = rowHeights.take(row).fold(0, (sum, item) => sum + item);
    img.compositeImage(canvas, entry.image, dstX: left, dstY: top);
    _drawShotLabel(canvas, entry.shotNumber,
        left: left, top: top, image: entry.image);
  }

  final isPreview = mode == StoryboardContactSheetMode.preview;
  return StoryboardContactSheet(
    bytes: Uint8List.fromList(
      isPreview ? img.encodeJpg(canvas, quality: 80) : img.encodePng(canvas),
    ),
    width: width,
    height: height,
    imageCount: images.length,
    mimeType: isPreview ? 'image/jpeg' : 'image/png',
  );
}

/// `compute` 所需的单参入口：页内预览在后台 isolate 中合成，避免阻塞画布。
StoryboardContactSheet? buildStoryboardPreviewContactSheet(
        List<({int shotNumber, Uint8List bytes})> sources) =>
    buildStoryboardContactSheet(
      sources,
      mode: StoryboardContactSheetMode.preview,
    );

/// `compute` 所需的单参入口：导出同样避免在交互线程解码多张首帧图。
StoryboardContactSheet? buildStoryboardExportContactSheet(
        List<({int shotNumber, Uint8List bytes})> sources) =>
    buildStoryboardContactSheet(
      sources,
      mode: StoryboardContactSheetMode.export,
    );

/// 将文件读取、解码和预览合成放在同一个后台 isolate，避免 UI 线程处理大图 I/O。
/// `shotNumber` 必须是分镜在完整列表里的真实序号（如 [Engine.storyboardImagePaths]
/// 返回的那样），调用方不能先过滤掉未生成分镜再重新计数。
StoryboardContactSheet? buildStoryboardPreviewContactSheetFromPaths(
        List<({int shotNumber, String absPath})> paths) =>
    buildStoryboardPreviewContactSheet(_readImageFiles(paths));

/// 将文件读取、解码和完整导出合成放在同一个后台 isolate。
StoryboardContactSheet? buildStoryboardExportContactSheetFromPaths(
        List<({int shotNumber, String absPath})> paths) =>
    buildStoryboardExportContactSheet(_readImageFiles(paths));

List<({int shotNumber, Uint8List bytes})> _readImageFiles(
  List<({int shotNumber, String absPath})> paths,
) {
  final result = <({int shotNumber, Uint8List bytes})>[];
  for (final entry in paths) {
    try {
      final file = File(entry.absPath);
      if (file.existsSync()) {
        result.add((
          shotNumber: entry.shotNumber,
          bytes: Uint8List.fromList(file.readAsBytesSync()),
        ));
      }
    } catch (_) {
      // 一张图片不可读不影响其余首帧合成，和 ToonFlow 的过滤语义一致。
    }
  }
  return result;
}

const _maxColumns = 5;
const _previewMaxWidth = 512;
// 导出保留比预览更多细节，但仍需要一个硬上限：分镜数量多时，未加界的原图
// 宽度会让合成画布和中间解码缓冲区的内存占用线性失控。2048px 足以覆盖当前
// 常见的生成分辨率（多数在 1024～2048 之间），超过时才降采样。
const _exportMaxWidth = 2048;

void _drawShotLabel(
  img.Image canvas,
  int shotNumber, {
  required int left,
  required int top,
  required img.Image image,
}) {
  final label = 'S${shotNumber.toString().padLeft(2, '0')}';
  final fontSize = math.max(
    14.0,
    math.min(image.width, image.height) * .06,
  );
  final padding = (fontSize * .4).round();
  final labelWidth = (label.length * fontSize * .65).round();
  final labelHeight = fontSize.round();
  final backgroundWidth = labelWidth + padding * 2;
  final backgroundHeight = labelHeight + padding * 2;
  img.fillRect(
    canvas,
    x1: left + 4,
    y1: top + 4,
    x2: left + 4 + backgroundWidth - 1,
    y2: top + 4 + backgroundHeight - 1,
    color: img.ColorRgba8(0, 0, 0, 140),
    radius: 4,
  );
  img.drawString(
    canvas,
    label,
    font: _labelFont(fontSize),
    x: left + 4 + padding,
    y: top + 4 + padding,
    color: img.ColorRgba8(255, 255, 255, 255),
  );
}

img.BitmapFont _labelFont(double fontSize) {
  if (fontSize >= 36) return img.arial48;
  if (fontSize >= 20) return img.arial24;
  return img.arial14;
}
