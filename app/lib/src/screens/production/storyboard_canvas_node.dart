// 分镜节点（画布内嵌，照抄 production/node/storyboard.vue 网格交互）：
// 工具栏（生成分镜/已选计数/全选/清空/批量生成图片/批量删除）+ 网格
// （彩色编号 tag/图片/状态/编辑/删除/生成/插入）。
// 偏差（文档化）：ToonFlow 用悬停展开的左右"+"按钮插入相邻分镜；本实现改为
// 每格操作菜单里的"插入分镜"项（触屏无 hover，菜单方式更适配双端）。
// 缩放滑块为会话内状态（不做跨会话持久化，MVP 简化，行为不影响功能完整性）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/storyboard.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import 'image_flow_editor.dart';

const _tagColors = [
  0xFF5BCCB3,
  0xFF9C7CFC,
  0xFFFBBF24,
  0xFFF97066,
  0xFF60A5FA,
  0xFFEC7BB0,
  0xFF34D399,
  0xFFC084FC,
];

class StoryboardCanvasNode extends ConsumerStatefulWidget {
  final int projectId;
  final int scriptId;
  const StoryboardCanvasNode(
      {super.key, required this.projectId, required this.scriptId});

  @override
  ConsumerState<StoryboardCanvasNode> createState() =>
      _StoryboardCanvasNodeState();
}

class _StoryboardCanvasNodeState extends ConsumerState<StoryboardCanvasNode> {
  final Set<int> _selected = {};
  double _cellSize = 150;

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _generateStoryboard() {
    ref.read(engineProvider).generateStoryboards(widget.projectId, widget.scriptId);
    _toast(context.l10n.productionStoryboardGenerating);
  }

  Future<void> _batchDelete() async {
    final l10n = context.l10n;
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(
            l10n.productionStoryboardConfirmBatchDeleteBody('${_selected.length}')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(engineProvider).deleteStoryboards(_selected.toList());
    setState(() => _selected.clear());
  }

  void _batchGenerateImages() {
    if (_selected.isEmpty) return;
    ref.read(engineProvider).batchGenerateStoryboardImages(
        widget.projectId, _selected.toList(),
        compulsory: true);
    _toast(context.l10n.productionStoryboardGenerate);
  }

  Future<void> _editRow(StoryboardRow row) async {
    final l10n = context.l10n;
    final promptCtl = TextEditingController(text: row.prompt ?? '');
    final descCtl = TextEditingController(text: row.videoDesc ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.productionStoryboardEditNode),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: promptCtl,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                  labelText: l10n.productionStoryboardPrompt,
                  hintText: l10n.productionStoryboardPromptPlaceholder),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtl,
              minLines: 2,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: l10n.productionStoryboardVideoDesc,
                  hintText: l10n.productionStoryboardVideoDescPlaceholder),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonSave)),
        ],
      ),
    );
    if (saved == true) {
      ref.read(engineProvider).editStoryboard(row.id,
          prompt: promptCtl.text, videoDesc: descCtl.text);
      setState(() {});
    }
  }

  Future<void> _deleteOne(StoryboardRow row) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(l10n.productionStoryboardConfirmDeleteBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(l10n.commonCancel)),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.df.danger),
              onPressed: () => Navigator.pop(c, true),
              child: Text(l10n.commonDelete)),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(engineProvider).deleteStoryboards([row.id]);
      setState(() => _selected.remove(row.id));
    }
  }

  void _openEditor(StoryboardRow row,
      {List<String> seedRefs = const [], int? flowId}) {
    showImageFlowEditor(
      context,
      ref,
      projectId: widget.projectId,
      flowId: flowId,
      seedReferenceRelPaths: seedRefs,
      onApply: (rel, savedFlowId) {
        ref
            .read(engineProvider)
            .setStoryboardImage(row.id, rel, flowId: savedFlowId);
        setState(() {});
      },
    );
  }

  void _insertAfter(List<StoryboardRow> rows, int index) {
    final engine = ref.read(engineProvider);
    final refs = <String>[
      if (rows[index].filePath != null) rows[index].filePath!,
      if (index + 1 < rows.length && rows[index + 1].filePath != null)
        rows[index + 1].filePath!,
    ];
    final newId = engine.addStoryboard(
      projectId: widget.projectId,
      scriptId: widget.scriptId,
      insertAfterIndex: rows[index].index,
    );
    setState(() {});
    if (refs.isNotEmpty) {
      final row = engine.storyboards(widget.scriptId).firstWhere((r) => r.id == newId);
      _openEditor(row, seedRefs: refs);
    }
  }

  Widget _cell(StoryboardRow row, int displayIndex) {
    final df = context.df;
    final l10n = context.l10n;
    final selected = _selected.contains(row.id);
    final tagColor = Color(_tagColors[displayIndex % _tagColors.length]);

    Widget stateOverlay() {
      switch (row.state) {
        case sbGenerating:
          return Container(
            color: Colors.black45,
            alignment: Alignment.center,
            child: const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        case sbFailed:
          return Container(
            color: Colors.black45,
            alignment: Alignment.center,
            child: Tooltip(
              message: localizeReason(l10n, row.reason) ?? '',
              child: Icon(Icons.error_outline, color: df.danger, size: 22),
            ),
          );
        default:
          return const SizedBox.shrink();
      }
    }

    return Container(
      width: _cellSize,
      height: _cellSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DFTokens.radiusControl),
        border: Border.all(color: selected ? df.primary : df.stroke, width: selected ? 2 : 1),
        color: df.surfaceMuted,
      ),
      child: Stack(fit: StackFit.expand, children: [
        if (row.filePath != null)
          Image.file(File(ref.read(engineProvider).mediaAbsPath(row.filePath!)),
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) =>
                  Icon(Icons.broken_image_outlined, color: df.textTertiary))
        else if (row.state != sbGenerating)
          Center(
            child: Text(l10n.productionStoryboardNotGenerated,
                style: TextStyle(fontSize: 11, color: df.textTertiary)),
          ),
        stateOverlay(),
        Positioned(
          top: 4,
          left: 4,
          child: Row(children: [
            Checkbox(
              value: selected,
              visualDensity: VisualDensity.compact,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(row.id);
                } else {
                  _selected.remove(row.id);
                }
              }),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: tagColor, borderRadius: BorderRadius.circular(4)),
              child: Text(
                  'S${(displayIndex + 1).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 10, color: Colors.white)),
            ),
          ]),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black.withValues(alpha: 0.5),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _miniIcon(Icons.bolt_outlined, () {
                ref.read(engineProvider).batchGenerateStoryboardImages(
                    widget.projectId, [row.id],
                    compulsory: true);
                setState(() {});
              }),
              _miniIcon(Icons.edit_outlined, () => _editRow(row)),
              _miniIcon(
                  Icons.auto_fix_high_outlined,
                  () => _openEditor(row,
                      flowId: row.flowId,
                      seedRefs:
                          row.filePath != null ? [row.filePath!] : const [])),
              _miniIcon(Icons.delete_outline, () => _deleteOne(row)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _miniIcon(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final rows = ref.watch(engineProvider).storyboards(widget.scriptId);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: Row(children: [
          Text(l10n.productionNodeStoryboardTitle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.zoom_out, size: 16),
            onPressed: () => setState(() => _cellSize = (_cellSize - 20).clamp(90, 260)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.zoom_in, size: 16),
            onPressed: () => setState(() => _cellSize = (_cellSize + 20).clamp(90, 260)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          if (rows.isEmpty)
            FilledButton.icon(
              onPressed: _generateStoryboard,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: Text(l10n.productionStoryboardGenerate,
                  style: const TextStyle(fontSize: 12)),
            )
          else ...[
            Text(l10n.productionStoryboardSelectedCount('${_selected.length}'),
                style: TextStyle(fontSize: 11, color: df.textSecondary)),
            TextButton(
              onPressed: () => setState(() => _selected
                ..clear()
                ..addAll(rows.map((r) => r.id))),
              child: Text(l10n.productionStoryboardSelectAll,
                  style: const TextStyle(fontSize: 12)),
            ),
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: Text(l10n.productionStoryboardClearSelection,
                  style: const TextStyle(fontSize: 12)),
            ),
            OutlinedButton(
              onPressed: _selected.isEmpty ? null : _batchGenerateImages,
              child: Text(l10n.productionStoryboardBatchGenerateImage,
                  style: const TextStyle(fontSize: 12)),
            ),
            OutlinedButton(
              onPressed: _selected.isEmpty ? null : _batchDelete,
              style: OutlinedButton.styleFrom(foregroundColor: df.danger),
              child: Text(l10n.assetsBatchDelete, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: rows.isEmpty
            ? const SizedBox.shrink()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (i, row) in rows.indexed)
                      GestureDetector(
                        onSecondaryTap: () => _showRowMenu(rows, i),
                        onLongPress: () => _showRowMenu(rows, i),
                        child: _cell(row, i),
                      ),
                  ],
                ),
              ),
      ),
    ]);
  }

  void _showRowMenu(List<StoryboardRow> rows, int index) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.add_box_outlined),
            title: Text(l10n.productionStoryboardInsertHint),
            onTap: () {
              Navigator.pop(c);
              _insertAfter(rows, index);
            },
          ),
        ]),
      ),
    );
  }
}
