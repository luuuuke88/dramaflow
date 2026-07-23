// 手册画廊（照抄 projectDialog 右栏）：100px 封面网格、底部名条、
// 选中 2px 主色描边、悬停编辑/删除/预览。
import 'dart:io';

import 'package:flutter/material.dart';

import '../../engine/manuals.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';

class ManualGallery extends StatelessWidget {
  final String title;
  final String addLabel;
  final List<ManualPack> packs;
  final String? selectedPackId;
  final ValueChanged<ManualPack?> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<ManualPack> onEdit;
  final ValueChanged<ManualPack> onDelete;

  const ManualGallery({
    super.key,
    required this.title,
    required this.addLabel,
    required this.packs,
    required this.selectedPackId,
    required this.onSelect,
    required this.onCreate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: df.surfaceMuted.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: df.stroke.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: df.textPrimary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: df.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${packs.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: df.primary,
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add, size: 14),
            label: Text(addLabel, style: const TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (packs.isEmpty)
          Container(
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: df.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(DFTokens.radiusControl),
              border: Border.all(color: df.stroke.withValues(alpha: 0.4)),
            ),
            child: Text(context.l10n.projectEmpty,
                style: TextStyle(color: df.textTertiary, fontSize: 12)),
          )
        else
          GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final pack in packs)
                _ManualCell(
                  pack: pack,
                  selected: pack.pack == selectedPackId,
                  onTap: () => onSelect(pack.pack == selectedPackId ? null : pack),
                  onEdit: () => onEdit(pack),
                  onDelete: () => onDelete(pack),
                  onPreview: () => showManualPackPreview(
                    context,
                    pack,
                    packs: packs,
                    selectedPackId: selectedPackId,
                    onSelect: onSelect,
                  ),
                ),
            ],
          ),
      ]),
    );
  }
}

class _ManualCell extends StatefulWidget {
  final ManualPack pack;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPreview;
  const _ManualCell({
    required this.pack,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onPreview,
  });

  @override
  State<_ManualCell> createState() => _ManualCellState();
}

class _ManualCellState extends State<_ManualCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final hasImages = widget.pack.images.isNotEmpty;
    final cover = hasImages ? File(widget.pack.images.first) : null;
    final isSelected = widget.selected;
    // 与 AppShell 的移动断点保持一致：触屏设备没有 hover，操作按钮必须常显。
    final compact = MediaQuery.sizeOf(context).width < 840;
    final showActions = _hover || compact;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AspectRatio(
          aspectRatio: 1.0,
          child: AnimatedContainer(
            duration: DFTokens.fast120,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                width: isSelected ? 2.5 : 1,
                color: isSelected ? df.primary : df.stroke,
              ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: df.primary.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
            color: df.surfaceMuted,
          ),
          child: Stack(fit: StackFit.expand, children: [
            // 封面图片或无图卡片背景
            if (cover != null) ...[
              Image.file(cover, fit: BoxFit.cover),
              // 渐变黑遮罩 (代替以前的硬黑条)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 48,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black87],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: Text(
                    widget.pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              // 无封面图卡片 (如导演手册/文字卡片)：渐变高级质感
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      df.surfaceMuted,
                      df.primary.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                // 窄屏 4 列时格子很小，内容按格子等比缩小而不是挤爆。
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.movie_filter_outlined,
                        size: 22,
                        color: isSelected ? df.primary : df.textSecondary,
                      ),
                      const SizedBox(height: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 96),
                        child: Text(
                          widget.pack.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? df.primary : df.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // 选中对勾 Badge
            if (isSelected)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: df.primary,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),

            // 悬停操作浮层（触屏无 hover：窄屏常显，但不加变暗遮罩以免盖住封面）
            if (showActions) ...[
              if (_hover) Container(color: Colors.black.withValues(alpha: 0.4)),
              if (hasImages)
                Positioned(
                  top: 4,
                  left: 4,
                  child: _MiniIcon(
                    icon: Icons.zoom_in,
                    tooltip: context.l10n.commonPreview,
                    onTap: widget.onPreview,
                  ),
                ),
              Positioned(
                top: 4,
                right: isSelected ? 24 : 4,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _MiniIcon(
                      icon: Icons.edit_outlined,
                      tooltip: context.l10n.commonEdit,
                      onTap: widget.onEdit),
                  const SizedBox(width: 4),
                  _MiniIcon(
                      icon: Icons.delete_outline,
                      tooltip: context.l10n.commonDelete,
                      onTap: widget.onDelete),
                ]),
              ),
            ],
          ]),
        ),
      ),
    ),
  );
}
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _MiniIcon(
      {required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}

/// 手册封面预览：支持浏览同类型全部手册、1:1 封面展示与下方“运用此手册”操作。
Future<void> showManualPackPreview(
  BuildContext context,
  ManualPack pack, {
  List<ManualPack> packs = const [],
  String? selectedPackId,
  ValueChanged<ManualPack?>? onSelect,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: _ManualPackPreviewCard(
        initialPack: pack,
        packs: packs.isEmpty ? [pack] : packs,
        selectedPackId: selectedPackId,
        onSelect: onSelect,
      ),
    ),
  );
}

class _ManualPackPreviewCard extends StatefulWidget {
  final ManualPack initialPack;
  final List<ManualPack> packs;
  final String? selectedPackId;
  final ValueChanged<ManualPack?>? onSelect;

  const _ManualPackPreviewCard({
    required this.initialPack,
    required this.packs,
    required this.selectedPackId,
    required this.onSelect,
  });

  @override
  State<_ManualPackPreviewCard> createState() => _ManualPackPreviewCardState();
}

class _ManualPackPreviewCardState extends State<_ManualPackPreviewCard> {
  late int _packIndex;
  int _imageIndex = 0;
  bool _showPrompt = false;

  @override
  void initState() {
    super.initState();
    final idx =
        widget.packs.indexWhere((p) => p.pack == widget.initialPack.pack);
    _packIndex = idx >= 0 ? idx : 0;
  }

  ManualPack get _currentPack => (widget.packs.isNotEmpty &&
          _packIndex >= 0 &&
          _packIndex < widget.packs.length)
      ? widget.packs[_packIndex]
      : widget.initialPack;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final pack = _currentPack;
    final images = pack.images;
    final imageCount = images.length;
    final packCount = widget.packs.length;
    final isSelected = pack.pack == widget.selectedPackId;

    // 获取样式提示词或描述文本
    final promptText = pack.data['art_prompt'] ??
        pack.data['prefix'] ??
        pack.data['README'];
    final hasPrompt = promptText != null && promptText.trim().isNotEmpty;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 540,
          maxHeight: 740,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: df.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: df.stroke),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部标题栏
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: df.stroke)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: df.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        context.l10n.projectDialogVisualManual,
                        style: TextStyle(
                          color: df.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              pack.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: df.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (packCount > 1) ...[
                            const SizedBox(width: 6),
                            Text(
                              '(${_packIndex + 1}/$packCount)',
                              style: TextStyle(
                                  color: df.textTertiary, fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                      tooltip: context.l10n.commonCancel,
                    ),
                  ],
                ),
              ),

              // 主体内容区域：1:1 封面展示与左右切换箭头
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: AspectRatio(
                            aspectRatio: 1.0, // 严格 1:1 封面比例
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (imageCount == 0)
                                  Container(
                                    color: df.surfaceMuted,
                                    child: Center(
                                      child: Icon(
                                        Icons.image_not_supported_outlined,
                                        color: df.textTertiary,
                                        size: 48,
                                      ),
                                    ),
                                  )
                                else ...[
                                  Image.file(
                                    File(images[_imageIndex]),
                                    fit: BoxFit.cover, // 1:1 正方形裁切充满
                                  ),
                                  // 图片左侧：切换到上一个视觉手册
                                  if (packCount > 1 && _packIndex > 0)
                                    Positioned(
                                      left: 10,
                                      top: 0,
                                      bottom: 0,
                                      child: Center(
                                        child: _CircleIconButton(
                                          icon: Icons.chevron_left,
                                          onPressed: () => setState(() {
                                            _packIndex--;
                                            _imageIndex = 0;
                                          }),
                                        ),
                                      ),
                                    ),
                                  // 图片右侧：切换到下一个视觉手册
                                  if (packCount > 1 &&
                                      _packIndex < packCount - 1)
                                    Positioned(
                                      right: 10,
                                      top: 0,
                                      bottom: 0,
                                      child: Center(
                                        child: _CircleIconButton(
                                          icon: Icons.chevron_right,
                                          onPressed: () => setState(() {
                                            _packIndex++;
                                            _imageIndex = 0;
                                          }),
                                        ),
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      // 多图缩略图切换条
                      if (imageCount > 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: SizedBox(
                            height: 48,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: imageCount,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 8),
                              itemBuilder: (context, i) {
                                final isSelectedImage = i == _imageIndex;
                                return GestureDetector(
                                  onTap: () => setState(() => _imageIndex = i),
                                  child: AnimatedContainer(
                                    duration: DFTokens.fast120,
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelectedImage
                                            ? df.primary
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Image.file(
                                      File(images[i]),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                      // 风格提示词/细节展开区域
                      if (hasPrompt)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Container(
                            decoration: BoxDecoration(
                              color: df.surfaceMuted,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: df.stroke),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => setState(
                                      () => _showPrompt = !_showPrompt),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    child: Row(
                                      children: [
                                        Icon(Icons.palette_outlined,
                                            size: 16, color: df.primary),
                                        const SizedBox(width: 6),
                                        Text(
                                          context.l10n.projectDialogVisualManualPrompt,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: df.textSecondary,
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          _showPrompt
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          size: 18,
                                          color: df.textTertiary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (_showPrompt)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 0, 12, 12),
                                    child: Text(
                                      promptText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: df.textTertiary,
                                        height: 1.4,
                                      ),
                                      maxLines: 8,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // 底部动作区域：运用此手册
              if (widget.onSelect != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: df.surfaceMuted,
                    border: Border(top: BorderSide(color: df.stroke)),
                  ),
                  child: Row(
                    children: [
                      if (isSelected) ...[
                        Icon(Icons.check_circle, size: 16, color: df.primary),
                        const SizedBox(width: 6),
                        Text(
                          context.l10n.projectDialogSelected,
                          style: TextStyle(
                            fontSize: 13,
                            color: df.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else ...[
                        Text(
                          context.l10n.projectDialogSelectArtStyle,
                          style: TextStyle(
                            fontSize: 13,
                            color: df.textTertiary,
                          ),
                        ),
                      ],
                      const Spacer(),
                      FilledButton.icon(
                        icon: Icon(
                          isSelected ? Icons.check : Icons.brush_outlined,
                          size: 16,
                        ),
                        label: Text(
                          isSelected
                              ? context.l10n.projectDialogSelected
                              : context.l10n.projectDialogOk,
                        ),
                        onPressed: isSelected
                            ? null
                            : () {
                                widget.onSelect?.call(pack);
                                Navigator.of(context).pop();
                              },
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  const _CircleIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    if (onPressed == null) return const SizedBox.shrink();
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}


