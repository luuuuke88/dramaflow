// 分镜节点（画布内嵌，照抄 production/node/storyboard.vue 网格交互）：
// 工具栏（生成分镜/已选计数/全选/清空/批量生成图片/批量删除）+ 网格
// （彩色编号 tag/图片/状态/编辑/删除/生成/插入）。
// 偏差（文档化）：ToonFlow 用悬停展开的左右"+"按钮插入相邻分镜；本实现改为
// 每格操作菜单里的"插入分镜"项（触屏无 hover，菜单方式更适配双端）。
// 缩放滑块为会话内状态（不做跨会话持久化，MVP 简化，行为不影响功能完整性）。
import 'dart:io';

import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/production_dependencies.dart';
import '../../engine/script_plan.dart';
import '../../engine/storyboard.dart';
import '../../engine/storyboard_table.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../util/storyboard_contact_sheet.dart';
import '../../widgets/policy_confirm.dart';
import 'image_flow_editor.dart';
import 'storyboard_gallery.dart';
import '../../widgets/df_canvas.dart';
import '../../widgets/df_toast.dart';

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
    showDFToast(context, msg);
  }

  Future<void> _generateStoryboard() async {
    final engine = ref.read(engineProvider);
    if (engine.scriptPlan(widget.projectId).trim().isEmpty ||
        engine
            .storyboardTable(widget.projectId, widget.scriptId)
            .trim()
            .isEmpty) {
      return;
    }
    final hasExisting = engine.storyboards(widget.scriptId).isNotEmpty;
    if (hasExisting &&
        !await confirmPolicyAction(
          context,
          engine.config,
          destructiveKey: 'replace_storyboards',
          description: context.l10n.storyboardReplaceDescription,
        )) {
      return;
    }
    if (!mounted) return;
    if (!await confirmPolicyAction(
      context,
      engine.config,
      taskClass: 'storyboard_generate',
      description: context.l10n.storyboardGenerateDescription,
    )) {
      return;
    }
    if (!mounted) return;
    final taskId = engine.generateStoryboards(
      widget.projectId,
      widget.scriptId,
      replaceExisting: hasExisting,
    );
    if (taskId == 0) return;
    ref.read(activeJobsProvider.notifier).poke();
    _toast(context.l10n.productionStoryboardGenerating);
  }

  Future<void> _batchDelete() async {
    final l10n = context.l10n;
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(l10n
            .productionStoryboardConfirmBatchDeleteBody('${_selected.length}')),
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

  Future<void> _batchGenerateImages() async {
    if (_selected.isEmpty) return;
    final config = ref.read(engineProvider).config;
    if (!await confirmPolicyAction(
      context,
      config,
      taskClass: 'storyboard_image_generation',
      description: context.l10n.productionStoryboardBatchGenerateImage,
      units: _selected.length,
    )) {
      return;
    }
    if (!mounted) return;
    ref.read(engineProvider).batchGenerateStoryboardImages(
        widget.projectId, _selected.toList(),
        compulsory: true);
    _toast(context.l10n.productionStoryboardGenerate);
  }

  /// 整屏预览全部有效首帧（对齐 ToonFlow previewImage 的单张 JPEG 网格）。
  Future<void> _previewAll() async {
    final engine = ref.read(engineProvider);
    final sheet = await compute(
      buildStoryboardPreviewContactSheetFromPaths,
      engine.storyboardImagePaths(widget.scriptId),
    );
    if (!mounted) return;
    if (sheet == null) {
      _toast(context.l10n.storyboardExportNoImages);
      return;
    }
    await showStoryboardContactSheetPreview(
      context,
      bytes: sheet.bytes,
      onDownload: _downloadAll,
    );
  }

  /// 导出单张原尺寸 PNG 网格（对齐 ToonFlow downPreviewImage）。
  Future<void> _downloadAll() async {
    final l10n = context.l10n;
    final engine = ref.read(engineProvider);
    final paths = engine.storyboardImagePaths(widget.scriptId);
    if (paths.isEmpty) {
      _toast(l10n.storyboardExportNoImages);
      return;
    }
    try {
      final sheet =
          await compute(buildStoryboardExportContactSheetFromPaths, paths);
      if (!mounted) return;
      if (sheet == null) {
        _toast(l10n.storyboardExportNoImages);
        return;
      }
      final fileName =
          'storyboardImagePreview-${DateTime.now().millisecondsSinceEpoch}.png';
      final location = await fs.getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          fs.XTypeGroup(label: 'png', extensions: ['png']),
        ],
      );
      if (location == null) return;
      await fs.XFile.fromData(
        sheet.bytes,
        mimeType: sheet.mimeType,
        name: fileName,
      ).saveTo(location.path);
      if (!mounted) return;
      _toast(l10n.storyboardExportSuccess('${sheet.imageCount}'));
    } catch (e) {
      if (!mounted) return;
      _toast(l10n.storyboardExportFailed('$e'));
    }
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
      scriptId: widget.scriptId,
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
      final row =
          engine.storyboards(widget.scriptId).firstWhere((r) => r.id == newId);
      _openEditor(row, seedRefs: refs);
    }
  }

  /// 在目标分镜前插入（引擎 addStoryboard 以 insertAfterIndex 为锚：
  /// 前插即 insertAfterIndex = 目标 index-1，随后整体后移）。种子参考图取前一格
  /// 与目标格的首帧图（对齐 _insertAfter 的相邻参考语义）。
  void _insertBefore(List<StoryboardRow> rows, int index) {
    final engine = ref.read(engineProvider);
    final refs = <String>[
      if (index - 1 >= 0 && rows[index - 1].filePath != null)
        rows[index - 1].filePath!,
      if (rows[index].filePath != null) rows[index].filePath!,
    ];
    final newId = engine.addStoryboard(
      projectId: widget.projectId,
      scriptId: widget.scriptId,
      insertAfterIndex: rows[index].index - 1,
    );
    setState(() {});
    if (refs.isNotEmpty) {
      final row =
          engine.storyboards(widget.scriptId).firstWhere((r) => r.id == newId);
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
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
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
        border: Border.all(
            color: selected ? df.primary : df.stroke, width: selected ? 2 : 1),
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
              child: Text('S${(displayIndex + 1).toString().padLeft(2, '0')}',
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
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _miniIcon(Icons.bolt_outlined, () async {
                    final config = ref.read(engineProvider).config;
                    if (!await confirmPolicyAction(
                      context,
                      config,
                      taskClass: 'storyboard_image_generation',
                      description: l10n.productionStoryboardBatchGenerateImage,
                    )) {
                      return;
                    }
                    if (!mounted) return;
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
                          seedRefs: row.filePath != null
                              ? [row.filePath!]
                              : const [])),
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
    final engine = ref.watch(engineProvider);
    final rows = engine.storyboards(widget.scriptId);
    final hasTable = engine
        .storyboardTable(widget.projectId, widget.scriptId)
        .trim()
        .isNotEmpty;
    final hasPlan = engine.scriptPlan(widget.projectId).trim().isNotEmpty;
    final stale = rows.isNotEmpty &&
        engine
            .productionDependencyState(
              widget.projectId,
              structuredStoryboardStateKey,
              scriptId: widget.scriptId,
            )
            .stale;

    // 拆解按钮：无分镜时是主动作（蓝色）；已有分镜后主角换成「生成图片」，
    // 它退居描边样式并改叫「重新拆分镜头」——它重做的是镜头拆解（会替换
    // S01…Sxx），卡片上的「未生成」说的是每个镜头的画面，两回事。
    final splitButton = Tooltip(
      message: l10n.storyboardGenerateTooltip,
      child: rows.isEmpty
          ? FilledButton.icon(
              key: Key('storyboard-generate-${widget.scriptId}'),
              onPressed: hasPlan && hasTable ? _generateStoryboard : null,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: Text(l10n.productionStoryboardGenerate,
                  style: const TextStyle(fontSize: 12)),
            )
          : OutlinedButton.icon(
              key: Key('storyboard-generate-${widget.scriptId}'),
              onPressed: hasPlan && hasTable ? _generateStoryboard : null,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: Text(l10n.productionStoryboardRegenerate,
                  style: const TextStyle(fontSize: 12)),
            ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // 单行工具栏：主动作在左、选择组居中、全局操作在右，缩放钉在行尾。
      // 之前是「标题+缩放」一行、按钮再挤两行，样式还混着链接和描边。
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (rows.isNotEmpty)
                  FilledButton.icon(
                    key: Key('storyboard-batch-image-${widget.scriptId}'),
                    onPressed: _selected.isEmpty ? null : _batchGenerateImages,
                    icon: const Icon(Icons.image_outlined, size: 14),
                    label: Text(
                      l10n.productionStoryboardBatchGenerateImage,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                splitButton,
                if (stale)
                  Tooltip(
                    message: l10n.productionNeedsRegeneration,
                    child: Container(
                      key: Key('storyboard-stale-${widget.scriptId}'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: df.warning.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l10n.productionStale,
                        style: TextStyle(fontSize: 11, color: df.warning),
                      ),
                    ),
                  ),
                if (rows.isNotEmpty) ...[
                  const SizedBox(width: 2),
                  Text(
                    l10n.productionStoryboardSelectedCount(
                        '${_selected.length}'),
                    style: TextStyle(fontSize: 11, color: df.textSecondary),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () => setState(() => _selected
                      ..clear()
                      ..addAll(rows.map((r) => r.id))),
                    child: Text(l10n.productionStoryboardSelectAll,
                        style: const TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed:
                        _selected.isEmpty ? null : () => setState(_selected.clear),
                    child: Text(l10n.productionStoryboardClearSelection,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          if (rows.isNotEmpty) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.storyboardPreviewAll,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              onPressed: _previewAll,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.storyboardExportAll,
              icon: const Icon(Icons.download_outlined, size: 16),
              onPressed: _downloadAll,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.assetsBatchDelete,
              icon: Icon(Icons.delete_outline, size: 16, color: df.danger),
              onPressed: _selected.isEmpty ? null : _batchDelete,
            ),
          ],
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.zoom_out, size: 16),
            onPressed: () =>
                setState(() => _cellSize = (_cellSize - 20).clamp(90, 260)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.zoom_in, size: 16),
            onPressed: () =>
                setState(() => _cellSize = (_cellSize + 20).clamp(90, 260)),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: rows.isEmpty
            ? const SizedBox.shrink()
            : DFCanvasScrollRegion(child: SingleChildScrollView(
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
      )),
    ]);
  }

  void _showRowMenu(List<StoryboardRow> rows, int index) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.first_page_outlined),
            title: Text(l10n.productionStoryboardInsertBefore),
            onTap: () {
              Navigator.pop(c);
              _insertBefore(rows, index);
            },
          ),
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
