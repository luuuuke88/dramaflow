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
  final String? selectedName;
  final ValueChanged<ManualPack?> onSelect;
  final VoidCallback onCreate;
  final ValueChanged<ManualPack> onEdit;
  final ValueChanged<ManualPack> onDelete;

  const ManualGallery({
    super.key,
    required this.title,
    required this.addLabel,
    required this.packs,
    required this.selectedName,
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
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        OutlinedButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add, size: 16),
          label: Text(addLabel, style: const TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact),
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
              selected: pack.name == selectedName,
              onTap: () =>
                  onSelect(pack.name == selectedName ? null : pack),
              onEdit: () => onEdit(pack),
              onDelete: () => onDelete(pack),
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
  const _ManualCell(
      {required this.pack,
      required this.selected,
      required this.onTap,
      required this.onEdit,
      required this.onDelete});

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  widget.pack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
            if (_hover) ...[
              Container(color: Colors.black.withValues(alpha: 0.35)),
              Positioned(
                top: 2,
                left: 2,
                child: _MiniIcon(
                    icon: Icons.edit_outlined,
                    tooltip: context.l10n.commonEdit,
                    onTap: widget.onEdit),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: _MiniIcon(
                    icon: Icons.delete_outline,
                    tooltip: context.l10n.commonDelete,
                    onTap: widget.onDelete),
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
