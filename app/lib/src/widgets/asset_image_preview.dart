import 'dart:io';

import 'package:flutter/material.dart';

import '../util/l10n_ext.dart';

/// 打开本地资产图片的大图预览。桌面和移动端共用同一缩放画布，路由形态随屏幕自适应。
Future<void> showAssetImagePreview(BuildContext context,
    {required String absPath}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      pageBuilder: (_, __, ___) => _AssetImagePreviewPage(absPath: absPath),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _AssetImagePreviewPage extends StatelessWidget {
  final String absPath;

  const _AssetImagePreviewPage({required this.absPath});

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
            child: IconButton(
              tooltip: l10n.commonClose,
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ),
      ]),
    );
  }
}
