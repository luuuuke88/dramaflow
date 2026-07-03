// 分镜首帧图整屏预览（对齐 ToonFlow storyboard.vue 的 preview-all 全屏查看器）：
// 可左右滑动的 PageView + InteractiveViewer（双指/滚轮缩放），带镜头序号标签；
// 未生成图片的分镜显示占位而不是崩溃。
import 'dart:io';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';

/// 单张预览条目：镜头序号（1 基）+ 图片绝对路径（null 表示未生成）。
class StoryboardPreviewItem {
  final int shotNumber;
  final String? absPath;
  const StoryboardPreviewItem({required this.shotNumber, this.absPath});
}

/// 打开整屏分镜预览。[items] 已按镜头顺序排列，[initialIndex] 为初始页。
Future<void> showStoryboardGallery(
  BuildContext context, {
  required List<StoryboardPreviewItem> items,
  int initialIndex = 0,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      barrierDismissible: true,
      pageBuilder: (_, __, ___) =>
          _StoryboardGalleryPage(items: items, initialIndex: initialIndex),
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _StoryboardGalleryPage extends StatefulWidget {
  final List<StoryboardPreviewItem> items;
  final int initialIndex;
  const _StoryboardGalleryPage(
      {required this.items, required this.initialIndex});

  @override
  State<_StoryboardGalleryPage> createState() => _StoryboardGalleryPageState();
}

class _StoryboardGalleryPageState extends State<_StoryboardGalleryPage> {
  late final PageController _controller;
  late int _current;

  @override
  void initState() {
    super.initState();
    final safeInitial =
        widget.items.isEmpty ? 0 : widget.initialIndex.clamp(0, widget.items.length - 1);
    _current = safeInitial;
    _controller = PageController(initialPage: safeInitial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = widget.items;
    final count = items.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          if (count == 0)
            Center(
              child: Text(
                l10n.storyboardPreviewEmpty,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            )
          else
            PageView.builder(
              controller: _controller,
              itemCount: count,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (context, i) => _page(items[i]),
            ),
          // 顶部：镜头序号（S01 / count）+ 关闭
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: DFTokens.s16, vertical: DFTokens.s8),
                child: Row(
                  children: [
                    if (count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: DFTokens.s12, vertical: DFTokens.s4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius:
                              BorderRadius.circular(DFTokens.radiusChip),
                        ),
                        child: Text(
                          l10n.storyboardPreviewCounter(
                            'S${items[_current].shotNumber.toString().padLeft(2, '0')}',
                            '${_current + 1}',
                            '$count',
                          ),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13),
                        ),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.commonCancel,
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

  Widget _page(StoryboardPreviewItem item) {
    final l10n = context.l10n;
    final path = item.absPath;
    final Widget content;
    if (path == null) {
      content = _placeholder(l10n.storyboardPreviewShotPlaceholder(
          'S${item.shotNumber.toString().padLeft(2, '0')}'));
    } else {
      content = Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) =>
            _placeholder(l10n.storyboardPreviewImageMissing),
      );
    }
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(child: content),
    );
  }

  Widget _placeholder(String label) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                color: Colors.white38, size: 48),
            const SizedBox(height: DFTokens.s12),
            Text(label,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
}
