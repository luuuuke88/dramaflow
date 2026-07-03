// 节点式图片编辑器（照抄 production/components/editImage，全屏弹窗）：
// upload 节点（参考图输入）+ generated 节点（AI 生成，选中态展开参数面板）+
// 连线（点击右侧手柄进入连接模式→点击目标节点左侧手柄完成，禁自环/禁重复）；
// 连线驱动 syncReferences：generated 节点的参考图 = 其入边来源节点的图片，
// 不是静态选择——这是本页唯一必须逐一复刻的非显然机制（见移植参照 §3）。
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import '../../engine/image_flow.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_canvas.dart';

const _nodeWidth = 260.0;
const _nodeCollapsedHeight = 220.0;
const _nodeExpandedHeight = 460.0;

class _NodeVM {
  final String id;
  final String type; // upload | generated
  Offset position;
  String? imageRel; // upload 节点当前图（相对路径）
  final TextEditingController promptCtl;
  String? generatedRel;
  String state; // idle | generating | done | failed
  String? errorText;
  bool selected;
  List<String> references; // 由连线推导，只读展示

  _NodeVM({
    required this.id,
    required this.type,
    required this.position,
    this.imageRel,
    String prompt = '',
    this.generatedRel,
    this.state = 'idle',
  })  : errorText = null,
        selected = false,
        references = const [],
        promptCtl = TextEditingController(text: prompt);
}

class _EdgeVM {
  final String id;
  final String source;
  final String target;
  const _EdgeVM({required this.id, required this.source, required this.target});
}

/// 打开编辑器；`onApply` 在用户点击某生成节点的"应用"按钮时回调
/// (生成结果相对路径, 保存后的 flowId)。
Future<void> showImageFlowEditor(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
  int? flowId,
  List<String> seedReferenceRelPaths = const [],
  required void Function(String rel, int flowId) onApply,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (c) => _ImageFlowEditorPage(
        projectId: projectId,
        flowId: flowId,
        seedReferenceRelPaths: seedReferenceRelPaths,
        onApply: onApply,
        ref: ref,
      ),
    ),
  );
}

class _ImageFlowEditorPage extends StatefulWidget {
  final int projectId;
  final int? flowId;
  final List<String> seedReferenceRelPaths;
  final void Function(String rel, int flowId) onApply;
  final WidgetRef ref;
  const _ImageFlowEditorPage({
    required this.projectId,
    required this.flowId,
    required this.seedReferenceRelPaths,
    required this.onApply,
    required this.ref,
  });

  @override
  State<_ImageFlowEditorPage> createState() => _ImageFlowEditorPageState();
}

class _ImageFlowEditorPageState extends State<_ImageFlowEditorPage> {
  final List<_NodeVM> _nodes = [];
  final List<_EdgeVM> _edges = [];
  String? _connectingFrom;
  int _seq = 0;
  int? _flowId;

  Engine get _engine => widget.ref.read(engineProvider);

  @override
  void initState() {
    super.initState();
    _flowId = widget.flowId;
    if (widget.flowId != null) {
      final data = _engine.getImageFlow(widget.flowId);
      for (final n in data.nodes) {
        _nodes.add(_NodeVM(
          id: n.id,
          type: n.type,
          position: Offset(n.x, n.y),
          imageRel: n.data['image'] as String?,
          prompt: (n.data['prompt'] as String?) ?? '',
          generatedRel: n.data['generatedImage'] as String?,
          state: n.data['generatedImage'] != null ? 'done' : 'idle',
        ));
      }
      for (final e in data.edges) {
        _edges.add(_EdgeVM(id: e.id, source: e.source, target: e.target));
      }
      _seq = _nodes.length;
    } else {
      for (final (i, rel) in widget.seedReferenceRelPaths.indexed) {
        _nodes.add(_NodeVM(
          id: 'u${_seq++}',
          type: 'upload',
          position: Offset(40, 40 + i * 260),
          imageRel: rel,
        ));
      }
      final genId = 'g${_seq++}';
      _nodes.add(_NodeVM(
        id: genId,
        type: 'generated',
        position: const Offset(400, 40),
      ));
      for (final upload in _nodes.where((n) => n.type == 'upload')) {
        _edges.add(_EdgeVM(
            id: 'e${_edges.length}', source: upload.id, target: genId));
      }
    }
    _syncReferences();
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.promptCtl.dispose();
    }
    super.dispose();
  }

  void _syncReferences() {
    for (final node in _nodes.where((n) => n.type == 'generated')) {
      final refs = <String>[];
      for (final edge in _edges.where((e) => e.target == node.id)) {
        final source = _nodes.where((n) => n.id == edge.source).firstOrNull;
        final rel = source?.type == 'upload'
            ? source?.imageRel
            : source?.generatedRel;
        if (rel != null) refs.add(rel);
      }
      node.references = refs;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addUploadNode() {
    setState(() {
      _nodes.add(_NodeVM(
          id: 'u${_seq++}', position: Offset(40, 40 + _nodes.length * 40),
          type: 'upload'));
    });
  }

  void _addGeneratedNode() {
    setState(() {
      _nodes.add(_NodeVM(
          id: 'g${_seq++}',
          position: Offset(400, 40 + _nodes.length * 40),
          type: 'generated'));
    });
  }

  void _deleteNode(String id) {
    setState(() {
      _nodes.removeWhere((n) => n.id == id);
      _edges.removeWhere((e) => e.source == id || e.target == id);
      _syncReferences();
    });
  }

  void _handleHandleTap(_NodeVM node, {required bool isSource}) {
    final l10n = context.l10n;
    if (isSource) {
      setState(() => _connectingFrom = node.id);
      return;
    }
    if (_connectingFrom == null) return;
    final sourceId = _connectingFrom!;
    if (sourceId == node.id) {
      setState(() => _connectingFrom = null);
      return;
    }
    final duplicate = _edges
        .any((e) => e.source == sourceId && e.target == node.id);
    if (duplicate || node.type != 'generated') {
      _toast(l10n.productionEditImageInvalidConnection);
      setState(() => _connectingFrom = null);
      return;
    }
    setState(() {
      _edges.add(_EdgeVM(id: 'e${_edges.length}_$_seq', source: sourceId, target: node.id));
      _seq++;
      _connectingFrom = null;
      _syncReferences();
    });
  }

  Future<void> _pickUploadImage(_NodeVM node) async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(label: 'image', extensions: ['png', 'jpg', 'jpeg', 'webp'])
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final saved = _engine.saveFlowUploadImage(widget.projectId, bytes);
    setState(() {
      node.imageRel = saved;
      _syncReferences();
    });
  }

  Future<void> _generate(_NodeVM node) async {
    final l10n = context.l10n;
    if (node.promptCtl.text.trim().isEmpty) {
      _toast(l10n.assetsGenFillPrompt);
      return;
    }
    setState(() {
      node.state = 'generating';
      node.errorText = null;
    });
    try {
      final refs = [
        for (final rel in node.references) _engine.mediaAbsPath(rel),
      ];
      final rel = await _engine.generateFlowImage(
        projectId: widget.projectId,
        prompt: node.promptCtl.text,
        referenceAbsPaths: refs,
      );
      setState(() {
        node.generatedRel = rel;
        node.state = 'done';
        _syncReferences();
      });
    } catch (e) {
      setState(() {
        node.state = 'failed';
        node.errorText = localizeError(context, e);
      });
    }
  }

  void _save() {
    final imageNodes = [
      for (final n in _nodes)
        ImageFlowNode(
          id: n.id,
          type: n.type,
          x: n.position.dx,
          y: n.position.dy,
          data: n.type == 'upload'
              ? {'image': n.imageRel}
              : {
                  'prompt': n.promptCtl.text,
                  'generatedImage': n.generatedRel,
                  'references': [for (final r in n.references) {'image': r}],
                },
        ),
    ];
    final imageEdges = [
      for (final e in _edges)
        ImageFlowEdge(id: e.id, source: e.source, target: e.target),
    ];
    _flowId = _engine.saveImageFlow(imageNodes, imageEdges, existingFlowId: _flowId);
    _toast(context.l10n.assetsGenImageSaved);
  }

  void _apply(_NodeVM node) {
    if (node.generatedRel == null) return;
    _save();
    widget.onApply(node.generatedRel!, _flowId!);
    Navigator.of(context).pop();
  }

  Widget _uploadNodeWidget(_NodeVM node) {
    final df = context.df;
    final l10n = context.l10n;
    return Container(
      width: _nodeWidth,
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(
            color: _connectingFrom == node.id ? df.primary : df.stroke,
            width: _connectingFrom == node.id ? 2 : 1),
        boxShadow: DFTokens.cardRest,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: df.textPrimary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Icon(Icons.image_outlined, size: 14, color: df.surface),
            const SizedBox(width: 6),
            Expanded(
              child: Text(l10n.productionEditImageUploadImage,
                  style: TextStyle(fontSize: 12, color: df.surface)),
            ),
            InkWell(
              onTap: () => _deleteNode(node.id),
              child: Icon(Icons.close, size: 14, color: df.surface),
            ),
          ]),
        ),
        InkWell(
          onTap: () => _pickUploadImage(node),
          child: Container(
            width: _nodeWidth,
            height: 160,
            color: df.surfaceMuted,
            child: node.imageRel == null
                ? Icon(Icons.add_photo_alternate_outlined,
                    color: df.textTertiary)
                : Image.file(File(_engine.mediaAbsPath(node.imageRel!)),
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Icon(Icons.broken_image_outlined,
                        color: df.textTertiary)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _HandleDot(
              onTap: () => _handleHandleTap(node, isSource: true),
              active: _connectingFrom == node.id,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _generatedNodeWidget(_NodeVM node) {
    final df = context.df;
    final l10n = context.l10n;
    return GestureDetector(
      onTap: () => setState(() => node.selected = !node.selected),
      child: Container(
        width: _nodeWidth,
        decoration: BoxDecoration(
          color: df.surface,
          borderRadius: BorderRadius.circular(DFTokens.radiusCard),
          border: Border.all(
              color: node.selected ? df.primary : df.stroke,
              width: node.selected ? 2 : 1),
          boxShadow: DFTokens.cardRest,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            _HandleDot(
              onTap: () => _handleHandleTap(node, isSource: false),
              active: false,
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                color: df.textPrimary,
                child: Row(children: [
                  Icon(Icons.auto_fix_high, size: 14, color: df.surface),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(l10n.productionEditImageImageGeneration,
                        style: TextStyle(fontSize: 12, color: df.surface)),
                  ),
                  InkWell(
                    onTap: () => _deleteNode(node.id),
                    child: Icon(Icons.close, size: 14, color: df.surface),
                  ),
                ]),
              ),
            ),
          ]),
          Container(
            width: _nodeWidth,
            height: 160,
            color: df.surfaceMuted,
            child: switch (node.state) {
              'generating' => Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(height: 6),
                    Text(l10n.productionEditImageGenerating,
                        style: TextStyle(fontSize: 11, color: df.textTertiary)),
                  ]),
                ),
              'done' when node.generatedRel != null => Image.file(
                  File(_engine.mediaAbsPath(node.generatedRel!)),
                  fit: BoxFit.cover,
                  errorBuilder: (c, e, s) =>
                      Icon(Icons.broken_image_outlined, color: df.textTertiary)),
              'failed' => Center(
                  child: Tooltip(
                    message: node.errorText ?? '',
                    child: Icon(Icons.error_outline, color: df.danger),
                  ),
                ),
              _ => Icon(Icons.image_not_supported_outlined,
                  color: df.textTertiary),
            },
          ),
          if (node.selected)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(children: [
                if (node.references.isNotEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final rel in node.references)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                File(_engine.mediaAbsPath(rel)),
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                TextField(
                  controller: node.promptCtl,
                  minLines: 2,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12),
                  decoration: InputDecoration(
                      hintText: l10n.productionEditImagePromptPlaceholder,
                      isDense: true),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: node.state == 'generating'
                          ? null
                          : () => _generate(node),
                      child: Text(l10n.productionEditImageGenerateBtn,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          node.generatedRel == null ? null : () => _apply(node),
                      child: Text(l10n.commonConfirm,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ]),
              ]),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.productionEditImageImageGeneration),
        actions: [
          TextButton.icon(
            onPressed: _addUploadNode,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(l10n.productionEditImageUpload),
          ),
          TextButton.icon(
            onPressed: _addGeneratedNode,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: Text(l10n.productionEditImageGenerate),
          ),
          IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              tooltip: l10n.commonSave),
          const SizedBox(width: 8),
        ],
      ),
      body: DFCanvas(
        nodes: [
          for (final n in _nodes)
            DFCanvasNode(
              id: n.id,
              position: n.position,
              size: Size(_nodeWidth,
                  n.type == 'generated' && n.selected
                      ? _nodeExpandedHeight
                      : _nodeCollapsedHeight),
              child: GestureDetector(
                onPanUpdate: (d) => setState(() => n.position += d.delta),
                child: n.type == 'upload'
                    ? _uploadNodeWidget(n)
                    : _generatedNodeWidget(n),
              ),
            ),
        ],
        edges: [
          for (final e in _edges)
            DFCanvasEdge(sourceId: e.source, targetId: e.target),
        ],
        fitOnInit: false,
      ),
    );
  }
}

class _HandleDot extends StatelessWidget {
  final VoidCallback onTap;
  final bool active;
  const _HandleDot({required this.onTap, required this.active});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(6),
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? df.accent : df.primary,
          border: Border.all(color: df.surface, width: 2),
        ),
      ),
    );
  }
}
