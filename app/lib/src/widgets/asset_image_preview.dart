import 'dart:io';

import 'package:clipboard/clipboard.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_codec;
import 'package:path/path.dart' as p;

import '../util/l10n_ext.dart';

class ImagePreviewActions {
  final Future<Uint8List> Function(String absPath) readImageBytes;
  final Future<void> Function(Uint8List bytes) copyImageBytes;
  final Future<void> Function(String absPath) saveImage;

  const ImagePreviewActions({
    required this.readImageBytes,
    required this.copyImageBytes,
    required this.saveImage,
  });

  static final system = ImagePreviewActions(
    readImageBytes: (absPath) => File(absPath).readAsBytes(),
    copyImageBytes: FlutterClipboard.copyImage,
    saveImage: _saveImageToUserPath,
  );
}

/// Native clipboard plugins accept PNG bytes. Keep an already-PNG source
/// untouched; other local image formats are decoded once and encoded for the
/// platform clipboard.
///
/// Local files aren't guaranteed to actually be PNG-encoded even when named
/// `.png` (see `MediaStore.saveImage`, which writes upstream bytes as-is), so
/// the decode/encode branch below is a real, CPU-bound possibility, not a
/// rare edge case. Callers must invoke this via `compute()` (see `_copy`
/// below) instead of calling it inline on the UI isolate — same pattern as
/// `buildStoryboardContactSheet` in storyboard_contact_sheet.dart.
Uint8List imageBytesForClipboard(Uint8List source) {
  const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (source.length >= pngSignature.length) {
    var isPng = true;
    for (var index = 0; index < pngSignature.length; index++) {
      if (source[index] != pngSignature[index]) {
        isPng = false;
        break;
      }
    }
    if (isPng) return source;
  }

  final decoded = image_codec.decodeImage(source);
  if (decoded == null) {
    throw ArgumentError.value(source, 'source', 'invalid_image_data');
  }
  return Uint8List.fromList(image_codec.encodePng(decoded));
}

Future<void> _saveImageToUserPath(String absPath) async {
  final source = File(absPath);
  if (!source.existsSync()) throw StateError('image source missing');
  final destination = await getSaveLocation(suggestedName: p.basename(absPath));
  if (destination == null) return;
  final data = await source.readAsBytes();
  await XFile.fromData(data, name: p.basename(absPath))
      .saveTo(destination.path);
}

/// 打开本地资产图片的大图预览。桌面和移动端共用同一缩放画布，路由形态随屏幕自适应。
Future<void> showAssetImagePreview(BuildContext context,
    {required String absPath, ImagePreviewActions? actions}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) =>
          AssetImagePreviewPage(absPath: absPath, actions: actions),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class AssetImagePreviewPage extends StatelessWidget {
  final String absPath;
  final ImagePreviewActions actions;

  AssetImagePreviewPage({
    super.key,
    required this.absPath,
    ImagePreviewActions? actions,
  }) : actions = actions ?? ImagePreviewActions.system;

  Future<void> _copy(BuildContext context) async {
    final l10n = context.l10n;
    try {
      final source = await actions.readImageBytes(absPath);
      // decodeImage/encodePng inside imageBytesForClipboard are CPU-bound;
      // run them on a background isolate so a non-PNG source can't jank the
      // UI thread while copying.
      final clipboardBytes = await compute(imageBytesForClipboard, source);
      await actions.copyImageBytes(clipboardBytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.imageActionCopied)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.imageActionCopyFailed)));
      }
    }
  }

  Future<void> _save(BuildContext context) async {
    final l10n = context.l10n;
    try {
      await actions.saveImage(absPath);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.imageActionSaveFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      key: const Key('asset-media-preview'),
      backgroundColor: Colors.transparent,
      body: Stack(children: [
        Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Image.file(
              File(absPath),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: const ValueKey('asset-image-copy'),
                tooltip: l10n.imageActionCopy,
                onPressed: () => _copy(context),
                icon: const Icon(Icons.copy_outlined, color: Colors.white),
              ),
              IconButton(
                key: const ValueKey('asset-image-save'),
                tooltip: l10n.imageActionSave,
                onPressed: () => _save(context),
                icon: const Icon(Icons.download_outlined, color: Colors.white),
              ),
              IconButton(
                tooltip: l10n.commonClose,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
