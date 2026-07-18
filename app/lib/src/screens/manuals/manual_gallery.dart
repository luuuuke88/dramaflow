// 手册画廊（照抄 projectDialog 右栏）：100px 封面网格、底部名条、
// 选中 2px 主色描边、悬停编辑/删除/预览。
import 'dart:io';

import 'package:flutter/material.dart';

import '../../engine/manuals.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/asset_image_preview.dart';

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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text(title,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        OutlinedButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add, size: 16),
          label: Text(addLabel, style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 44)),
        ),
      ]),
      const SizedBox(height: 8),
      if (packs.isEmpty)
        Container(
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: df.surfaceMuted,
            borderRadius: BorderRadius.circular(DFTokens.radiusControl),
            border: Border.all(color: df.stroke),
          ),
          child: Text(context.l10n.projectEmpty,
              style: TextStyle(color: df.textTertiary, fontSize: 12)),
        )
      else
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final pack in packs)
            _ManualCell(
              pack: pack,
              selected: pack.pack == selectedPackId,
              onTap: () => onSelect(pack.pack == selectedPackId ? null : pack),
              onEdit: () => onEdit(pack),
              onDelete: () => onDelete(pack),
              onPreview: pack.images.isEmpty
                  ? null
                  : () => showAssetImagePreview(context,
                      absPath: pack.images.first),
            ),
        ]),
    ]);
  }
}

class _ManualCell extends StatefulWidget {
  final ManualPack pack;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onPreview;
  const _ManualCell(
      {required this.pack,
      required this.selected,
      required this.onTap,
      required this.onEdit,
      required this.onDelete,
      required this.onPreview});

  @override
  State<_ManualCell> createState() => _ManualCellState();
}

class _ManualCellState extends State<_ManualCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    final cover =
        widget.pack.images.isEmpty ? null : File(widget.pack.images.first);
    // 与 AppShell 的移动断点保持一致：700-839dp 的平板仍走移动壳，
    // 触控没有 hover，操作必须常显。
    final compact = MediaQuery.sizeOf(context).width < 840;
    final showActions = _hover || compact;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DFTokens.fast120,
          width: 100,
          height: 100,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              width: 2,
              color: widget.selected ? df.primary : Colors.transparent,
            ),
            color: df.surfaceMuted,
          ),
          child: Stack(fit: StackFit.expand, children: [
            if (cover != null)
              Image.file(cover, fit: BoxFit.cover)
            else
              Icon(Icons.palette_outlined, color: df.textTertiary),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  widget.pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            if (showActions) ...[
              Container(color: Colors.black.withValues(alpha: 0.35)),
              Positioned(
                top: 2,
                left: 2,
                child: _MiniIcon(
                    icon: Icons.edit_outlined,
                    tooltip: context.l10n.commonEdit,
                    alignment: Alignment.topLeft,
                    onTap: widget.onEdit),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: _MiniIcon(
                    icon: Icons.delete_outline,
                    tooltip: context.l10n.commonDelete,
                    alignment: Alignment.topRight,
                    onTap: widget.onDelete),
              ),
              if (widget.onPreview != null)
                Positioned(
                  bottom: 2,
                  left: 2,
                  child: _MiniIcon(
                      icon: Icons.zoom_in_outlined,
                      tooltip: context.l10n.assetsColPreview,
                      alignment: Alignment.bottomLeft,
                      onTap: widget.onPreview!),
                ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  // 视觉小图标贴在缩略图角落，但点击热区扩到 44x44dp（触屏最小点击面积指引）；
  // alignment 决定小图标在热区里贴哪个角，保持贴角视觉不变。
  final Alignment alignment;
  const _MiniIcon(
      {required this.icon,
      required this.tooltip,
      required this.onTap,
      this.alignment = Alignment.topLeft});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Align(
              alignment: alignment,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, size: 14, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
