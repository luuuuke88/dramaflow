// 分镜联系表预览：对齐 ToonFlow previewImage 的单张五列 JPEG 网格。
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';

Future<void> showStoryboardContactSheetPreview(
  BuildContext context, {
  required Uint8List bytes,
  Future<void> Function()? onDownload,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) => _StoryboardContactSheetPreview(
        bytes: bytes,
        onDownload: onDownload,
      ),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _StoryboardContactSheetPreview extends StatelessWidget {
  final Uint8List bytes;
  final Future<void> Function()? onDownload;

  const _StoryboardContactSheetPreview({
    required this.bytes,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('storyboard-contact-sheet-preview'),
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: .1,
              maxScale: 10,
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Text(
                  context.l10n.storyboardPreviewImageMissing,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DFTokens.s8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onDownload != null)
                      IconButton(
                        tooltip: context.l10n.storyboardExportAll,
                        icon: const Icon(Icons.download_outlined,
                            color: Colors.white),
                        onPressed: onDownload,
                      ),
                    IconButton(
                      tooltip: context.l10n.commonCancel,
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
