// 节点式图片编辑器（照抄 production/components/editImage，全屏弹窗）：
// upload 节点（参考图输入）+ generated 节点（AI 生成，选中态展开参数面板）+
// 连线（点击右侧手柄进入连接模式→点击目标节点左侧手柄完成，禁自环/禁重复）；
// 连线驱动 syncReferences：generated 节点的参考图 = 其入边来源节点的图片，
// 不是静态选择——这是本页唯一必须逐一复刻的非显然机制（见移植参照 §3）。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../engine/assets.dart';
import '../../engine/engine.dart';
import '../../engine/image_flow.dart';
import '../../engine/storyboard.dart';
import '../project/model_select.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/error_l10n.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_canvas.dart';
import '../../widgets/common.dart';

const _nodeWidth = 260.0;
// upload 节点含头部(≈32)+图片(160)+手柄行(≈36)约 228，故折叠高留足余量避免溢出。
const _nodeCollapsedHeight = 236.0;
// 选中态展开后要容纳：参考图缩略图 + prompt + 三个参数选择器 + 操作按钮，
// 故较未选中态更高（对齐 ToonFlow generatedNode 展开的 .parameter 面板）。
const _nodeExpandedHeight = 560.0;

// 画幅/清晰度为静态枚举（对齐 ToonFlow t-option 硬编码值）。
const _ratioOptions = ['16:9', '9:16', '1:1'];
const _qualityOptions = ['1K', '2K', '4K'];

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
  // 生成参数（对齐 ToonFlow generatedNode 的 data.model/ratio/quality）：
  // model 为 'providerId:modelId'（enabled 图片模型），ratio/quality 为静态枚举值。
  String? model;
  String? ratio;
  String? quality;

  _NodeVM({
    required this.id,
    required this.type,
    required this.position,
    this.imageRel,
    String prompt = '',
    this.generatedRel,
    this.state = 'idle',
    this.model,
    this.ratio,
    this.quality,
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
/// `scriptId` 可选：提供时"从分镜选择"图片来源可用（列出该剧集已生成首帧图）。
Future<void> showImageFlowEditor(
  BuildContext context,
  WidgetRef ref, {
  required int projectId,
  int? flowId,
  int? scriptId,
  List<String> seedReferenceRelPaths = const [],
  required void Function(String rel, int flowId) onApply,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (c) => _ImageFlowEditorPage(
        projectId: projectId,
        flowId: flowId,
        scriptId: scriptId,
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
  final int? scriptId;
  final List<String> seedReferenceRelPaths;
  final void Function(String rel, int flowId) onApply;
  final WidgetRef ref;
  const _ImageFlowEditorPage({
    required this.projectId,
    required this.flowId,
    required this.scriptId,
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

  // 生成参数默认值（对齐 ToonFlow onMounted：model=project.imageModel、
  // quality=project.imageQuality、ratio=project.videoRatio ?? '16:9'）。
  String? _defaultModel;
  String? _defaultQuality;
  String _defaultRatio = '16:9';

  // enabled 图片模型选项（providerId:modelId），异步加载后填充。
  List<ModelOption> _imageModels = const [];

  Engine get _engine => widget.ref.read(engineProvider);

  @override
  void initState() {
    super.initState();
    _flowId = widget.flowId;
    _loadProjectDefaults();
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
          model: (n.data['model'] as String?)?.trim().isEmpty ?? true
              ? _defaultModel
              : n.data['model'] as String?,
          ratio: (n.data['ratio'] as String?)?.trim().isEmpty ?? true
              ? _defaultRatio
              : n.data['ratio'] as String?,
          quality: (n.data['quality'] as String?)?.trim().isEmpty ?? true
              ? _defaultQuality
              : n.data['quality'] as String?,
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
        model: _defaultModel,
        ratio: _defaultRatio,
        quality: _defaultQuality,
      ));
      for (final upload in _nodes.where((n) => n.type == 'upload')) {
        _edges.add(
            _EdgeVM(id: 'e${_edges.length}', source: upload.id, target: genId));
      }
    }
    _syncReferences();
    _loadImageModels();
  }

  /// 从当前项目读取默认 model/quality/ratio（对齐 ToonFlow onMounted）。
  void _loadProjectDefaults() {
    try {
      final project =
          _engine.projects().where((p) => p.id == widget.projectId).firstOrNull;
      final model = project?.imageModel?.trim();
      final quality = project?.imageQuality?.trim();
      final ratio = project?.videoRatio?.trim();
      _defaultModel = (model?.isEmpty ?? true) ? null : model;
      _defaultQuality = (quality?.isEmpty ?? true) ? null : quality;
      _defaultRatio = (ratio?.isEmpty ?? true) ? '16:9' : ratio!;
    } catch (_) {
      _defaultRatio = '16:9';
    }
  }

  /// 异步加载 enabled 图片模型（复用 modelSelect 的 providerId:modelId 语义）。
  Future<void> _loadImageModels() async {
    try {
      final options =
          await widget.ref.read(modelOptionsProvider('image').future);
      if (!mounted) return;
      setState(() {
        _imageModels = options;
        // 项目默认模型可能不在 enabled 列表里；若节点未选且默认无效则留空待选。
        for (final node in _nodes.where((n) => n.type == 'generated')) {
          if (node.model != null &&
              !options.any((o) => o.value == node.model)) {
            node.model = null;
          }
        }
      });
    } catch (_) {
      // 加载失败时保持空列表；模型选择器回退为只读占位（见 _modelSelectField）。
    }
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
        final rel =
            source?.type == 'upload' ? source?.imageRel : source?.generatedRel;
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
          id: 'u${_seq++}',
          position: Offset(40, 40 + _nodes.length * 40),
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

  /// 删除单条连线（点击边中点的 × 触发），并重算连线驱动的参考图。
  void _removeEdge(String edgeId) {
    setState(() {
      _edges.removeWhere((e) => e.id == edgeId);
      _syncReferences();
    });
    _toast(context.l10n.imageEditorEdgeRemoved);
  }

  /// 节点在画布上的当前尺寸（与 DFCanvasNode.size 一致，供边中点定位）。
  Size _nodeSize(_NodeVM n) => Size(
      _nodeWidth,
      n.type == 'generated' && n.selected
          ? _nodeExpandedHeight
          : _nodeCollapsedHeight);

  /// 连线中点坐标（与 df_canvas 边绘制口径一致：源右侧中点→目标左侧中点的
  /// 三次贝塞尔，取参数 t=0.5 处）。用于放置删除连线的 × 手柄。
  Offset? _edgeMidpoint(_EdgeVM e) {
    final source = _nodes.where((n) => n.id == e.source).firstOrNull;
    final target = _nodes.where((n) => n.id == e.target).firstOrNull;
    if (source == null || target == null) return null;
    final sSize = _nodeSize(source);
    final tSize = _nodeSize(target);
    final start = Offset(source.position.dx + sSize.width,
        source.position.dy + sSize.height / 2);
    final end =
        Offset(target.position.dx, target.position.dy + tSize.height / 2);
    final ctrlX = (start.dx + end.dx) / 2;
    // 三次贝塞尔 t=0.5：控制点 (ctrlX,start.y) 与 (ctrlX,end.y)。
    const t = 0.5;
    final mt = 1 - t;
    final x = mt * mt * mt * start.dx +
        3 * mt * mt * t * ctrlX +
        3 * mt * t * t * ctrlX +
        t * t * t * end.dx;
    final y = mt * mt * mt * start.dy +
        3 * mt * mt * t * start.dy +
        3 * mt * t * t * end.dy +
        t * t * t * end.dy;
    return Offset(x, y);
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
    final duplicate =
        _edges.any((e) => e.source == sourceId && e.target == node.id);
    if (duplicate || node.type != 'generated') {
      _toast(l10n.productionEditImageInvalidConnection);
      setState(() => _connectingFrom = null);
      return;
    }
    setState(() {
      _edges.add(_EdgeVM(
          id: 'e${_edges.length}_$_seq', source: sourceId, target: node.id));
      _seq++;
      _connectingFrom = null;
      _syncReferences();
    });
  }

  /// upload 节点选图：先选来源（本地文件 / 素材库 / 分镜），再取对应图片。
  /// 对齐 ToonFlow editImage 上传节点的多来源选图（本地上传之外还可引用已有资产/分镜图）。
  Future<void> _pickUploadImage(_NodeVM node) async {
    final l10n = context.l10n;
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(l10n.imageEditorPickLocalFile),
            onTap: () => Navigator.pop(c, 'local'),
          ),
          ListTile(
            leading: const Icon(Icons.collections_outlined),
            title: Text(l10n.imageEditorPickFromAssets),
            onTap: () => Navigator.pop(c, 'assets'),
          ),
          ListTile(
            leading: const Icon(Icons.grid_view_outlined),
            title: Text(l10n.imageEditorPickFromStoryboard),
            onTap: () => Navigator.pop(c, 'storyboard'),
          ),
        ]),
      ),
    );
    if (!mounted || source == null) return;
    switch (source) {
      case 'local':
        await _pickLocalImage(node);
      case 'assets':
        await _pickFromLibrary(node, fromStoryboard: false);
      case 'storyboard':
        await _pickFromLibrary(node, fromStoryboard: true);
    }
  }

  Future<void> _pickLocalImage(_NodeVM node) async {
    final file = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
          label: 'image', extensions: ['png', 'jpg', 'jpeg', 'webp'])
    ]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final saved = _engine.saveFlowUploadImage(widget.projectId, bytes);
    setState(() {
      node.imageRel = saved;
      _syncReferences();
    });
  }

  /// 从素材库或分镜里挑一张已生成图片作为参考（返回其相对路径）。
  Future<void> _pickFromLibrary(_NodeVM node,
      {required bool fromStoryboard}) async {
    final items = fromStoryboard ? _storyboardImageItems() : _assetImageItems();
    final rel = await showDFAdaptiveDialog<String>(
      context,
      title: context.l10n.imageEditorPickImageTitle,
      desktopWidthFactor: 0.6,
      builder: (_) => _LibraryPicker(
        engine: _engine,
        items: items,
        emptyText: fromStoryboard
            ? context.l10n.imageEditorNoStoryboardImages
            : context.l10n.imageEditorNoAssetsImages,
      ),
    );
    if (!mounted || rel == null) return;
    setState(() {
      node.imageRel = rel;
      _syncReferences();
    });
  }

  /// 素材库已选中图（跨 role/scene/tool；仅返回有 filePath 者）。
  List<_PickItem> _assetImageItems() {
    final out = <_PickItem>[];
    for (final type in const ['role', 'scene', 'tool']) {
      final res = _engine.getAssets(widget.projectId, type: type, limit: 999);
      for (final a in res.data) {
        if (a.filePath != null && a.filePath!.isNotEmpty) {
          out.add(_PickItem(rel: a.filePath!, label: a.name ?? ''));
        }
      }
    }
    return out;
  }

  /// 本剧集已生成首帧图的分镜（按镜头序号编号）。
  List<_PickItem> _storyboardImageItems() {
    final scriptId = widget.scriptId;
    if (scriptId == null) return const [];
    final rows = _engine.storyboards(scriptId);
    final out = <_PickItem>[];
    for (final (i, r) in rows.indexed) {
      if (r.filePath != null && r.filePath!.isNotEmpty) {
        out.add(_PickItem(
            rel: r.filePath!, label: 'S${(i + 1).toString().padLeft(2, '0')}'));
      }
    }
    return out;
  }

  /// 生成前置校验：prompt + model + quality + ratio 均必填（对齐 ToonFlow
  /// handleGenerate 的必选校验；按钮禁用态也据此）。
  bool _canGenerate(_NodeVM node) =>
      node.promptCtl.text.trim().isNotEmpty &&
      (node.model?.isNotEmpty ?? false) &&
      (node.quality?.isNotEmpty ?? false) &&
      (node.ratio?.isNotEmpty ?? false);

  Future<void> _generate(_NodeVM node) async {
    final l10n = context.l10n;
    // 校验顺序对齐 ToonFlow handleGenerate：prompt→model→quality→ratio。
    if (node.promptCtl.text.trim().isEmpty) {
      _toast(l10n.assetsGenFillPrompt);
      return;
    }
    if (node.model?.isEmpty ?? true) {
      _toast(l10n.imageEditorSelectModel);
      return;
    }
    if (node.quality?.isEmpty ?? true) {
      _toast(l10n.imageEditorSelectQuality);
      return;
    }
    if (node.ratio?.isEmpty ?? true) {
      _toast(l10n.imageEditorSelectRatio);
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
        model: node.model,
        ratio: node.ratio,
        quality: node.quality,
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

  Future<void> _repaint(_NodeVM node) async {
    final sourceRel = node.generatedRel;
    if (sourceRel == null) return;
    final instruction = await showRepaintInstructionDialog(context);
    if (!mounted || instruction == null) return;
    setState(() {
      node.state = 'generating';
      node.errorText = null;
    });
    try {
      final rel = await _engine.generateFlowImage(
        projectId: widget.projectId,
        prompt: node.promptCtl.text,
        referenceAbsPaths: [_engine.mediaAbsPath(sourceRel)],
        editInstruction: instruction,
        model: node.model,
        ratio: node.ratio,
        quality: node.quality,
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

  Future<void> _localInpaint(_NodeVM node) async {
    final sourceRel = node.generatedRel;
    if (sourceRel == null) return;
    final sourceAbs = _engine.mediaAbsPath(sourceRel);
    final result = await _showMaskInpaintDialog(context, sourceAbs);
    if (!mounted || result == null) return;
    final maskRel = _engine.saveFlowMaskImage(widget.projectId, result.maskPng);
    setState(() {
      node.state = 'generating';
      node.errorText = null;
    });
    try {
      final rel = await _engine.generateFlowImage(
        projectId: widget.projectId,
        prompt: node.promptCtl.text,
        referenceAbsPaths: [sourceAbs],
        editInstruction: result.instruction,
        maskAbsPath: _engine.mediaAbsPath(maskRel),
        model: node.model,
        ratio: node.ratio,
        quality: node.quality,
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
                  'references': [
                    for (final r in n.references) {'image': r}
                  ],
                  // 生成参数随节点持久化（对齐 ToonFlow data.model/ratio/quality）。
                  'model': n.model,
                  'ratio': n.ratio,
                  'quality': n.quality,
                },
        ),
    ];
    final imageEdges = [
      for (final e in _edges)
        ImageFlowEdge(id: e.id, source: e.source, target: e.target),
    ];
    _flowId =
        _engine.saveImageFlow(imageNodes, imageEdges, existingFlowId: _flowId);
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

  /// 模型选择器：填充 enabled 图片模型（providerId:modelId）。
  /// 若引擎当前无可用图片模型，则退化为只读展示节点已绑定/项目默认模型
  /// （对齐移植说明：无干净模型列表时不臆造，显示已绑定模型即可）。
  Widget _modelSelectField(_NodeVM node) {
    final df = context.df;
    final l10n = context.l10n;
    if (_imageModels.isEmpty) {
      final bound = node.model;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: df.stroke),
          borderRadius: BorderRadius.circular(6),
          color: df.surfaceMuted,
        ),
        child: Row(children: [
          Icon(Icons.smart_toy_outlined, size: 14, color: df.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              bound == null || bound.isEmpty
                  ? l10n.imageEditorNoImageModel
                  : bound,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: df.textSecondary),
            ),
          ),
        ]),
      );
    }
    final valid =
        _imageModels.any((o) => o.value == node.model) ? node.model : null;
    return DropdownButtonFormField<String>(
      initialValue: valid,
      isExpanded: true,
      isDense: true,
      hint: Text(l10n.imageEditorModel,
          style: TextStyle(color: df.textTertiary, fontSize: 12)),
      decoration: const InputDecoration(isDense: true),
      style: TextStyle(fontSize: 12, color: df.textPrimary),
      items: [
        for (final o in _imageModels)
          DropdownMenuItem(
            value: o.value,
            child: Text(o.label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
      ],
      onChanged: (v) => setState(() => node.model = v),
    );
  }

  /// 静态枚举选择器（画幅/清晰度共用）。
  Widget _enumSelectField({
    required String? value,
    required String hint,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    final df = context.df;
    final valid = options.contains(value) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: valid,
      isExpanded: true,
      isDense: true,
      hint: Text(hint, style: TextStyle(color: df.textTertiary, fontSize: 12)),
      decoration: const InputDecoration(isDense: true),
      style: TextStyle(fontSize: 12, color: df.textPrimary),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(o, style: const TextStyle(fontSize: 12)),
          ),
      ],
      onChanged: onChanged,
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
          DFCanvasDragRegion(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                _HandleDot(
                  onTap: () => _handleHandleTap(node, isSource: false),
                  active: false,
                ),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            const SizedBox(height: 6),
                            Text(l10n.productionEditImageGenerating,
                                style: TextStyle(
                                    fontSize: 11, color: df.textTertiary)),
                          ]),
                    ),
                  'done' when node.generatedRel != null => Image.file(
                      File(_engine.mediaAbsPath(node.generatedRel!)),
                      fit: BoxFit.cover,
                      errorBuilder: (c, e, s) => Icon(
                          Icons.broken_image_outlined,
                          color: df.textTertiary)),
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
            ]),
          ),
          if (node.selected)
            DFCanvasDragRegion(
              movesNode: false,
              child: Padding(
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
                  // 模型选择（enabled 图片模型；对齐 ToonFlow modelSelect）。
                  _modelSelectField(node),
                  const SizedBox(height: 6),
                  // 画幅 + 清晰度（静态枚举；对齐 ToonFlow 两个 t-select）。
                  Row(children: [
                    Expanded(
                      child: _enumSelectField(
                        value: node.ratio,
                        hint: l10n.imageEditorRatio,
                        options: _ratioOptions,
                        onChanged: (v) => setState(() => node.ratio = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _enumSelectField(
                        value: node.quality,
                        hint: l10n.imageEditorQuality,
                        options: _qualityOptions,
                        onChanged: (v) => setState(() => node.quality = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            node.state == 'generating' || !_canGenerate(node)
                                ? null
                                : () => _generate(node),
                        child: Text(l10n.productionEditImageGenerateBtn,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton(
                        onPressed: node.generatedRel == null
                            ? null
                            : () => _apply(node),
                        child: Text(l10n.commonConfirm,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ]),
                  if (node.generatedRel != null) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: node.state == 'generating'
                            ? null
                            : () => _repaint(node),
                        icon: const Icon(Icons.brush_outlined, size: 16),
                        label: Text(l10n.repaintAction,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: node.state == 'generating'
                            ? null
                            : () => _localInpaint(node),
                        icon: const Icon(Icons.gesture_rounded, size: 16),
                        label: Text(l10n.inpaintAction,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final compact = MediaQuery.sizeOf(context).width < 600;
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
              size: _nodeSize(n),
              onDragUpdate: (delta) => setState(() => n.position += delta),
              child: n.type == 'upload'
                  ? DFCanvasDragRegion(child: _uploadNodeWidget(n))
                  : _generatedNodeWidget(n),
            ),
          // 每条连线中点放一个 × 手柄，点击删除该连线（对齐 ToonFlow removeLine）。
          for (final e in _edges)
            if (_edgeMidpoint(e) case final mid?)
              DFCanvasNode(
                id: 'edgeDel_${e.id}',
                position: mid - const Offset(11, 11),
                size: const Size(22, 22),
                child: _EdgeDeleteDot(
                  tooltip: l10n.imageEditorRemoveEdge,
                  onTap: () => _removeEdge(e.id),
                ),
              ),
        ],
        edges: [
          for (final e in _edges)
            DFCanvasEdge(sourceId: e.source, targetId: e.target),
        ],
        fitOnInit: compact,
      ),
    );
  }
}

class _MaskEditResult {
  final String instruction;
  final Uint8List maskPng;

  const _MaskEditResult({required this.instruction, required this.maskPng});
}

class _ImagePixelSize {
  final int width;
  final int height;

  const _ImagePixelSize(this.width, this.height);
}

Future<_MaskEditResult?> _showMaskInpaintDialog(
  BuildContext context,
  String imageAbsPath,
) {
  return showDialog<_MaskEditResult>(
    context: context,
    builder: (context) => _MaskInpaintDialog(imageAbsPath: imageAbsPath),
  );
}

class _MaskInpaintDialog extends StatefulWidget {
  final String imageAbsPath;

  const _MaskInpaintDialog({required this.imageAbsPath});

  @override
  State<_MaskInpaintDialog> createState() => _MaskInpaintDialogState();
}

class _MaskInpaintDialogState extends State<_MaskInpaintDialog> {
  final _controller = TextEditingController();
  final List<Offset?> _points = [];
  Size _paintSize = Size.zero;
  String? _instructionError;
  String? _maskError;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _addPoint(Offset point) {
    final size = _paintSize;
    final clamped = size.isEmpty
        ? point
        : Offset(
            point.dx.clamp(0.0, size.width).toDouble(),
            point.dy.clamp(0.0, size.height).toDouble(),
          );
    setState(() {
      _points.add(clamped);
      _maskError = null;
    });
  }

  _ImagePixelSize _readSourceImageSize() {
    final bytes = File(widget.imageAbsPath).readAsBytesSync();
    return _parsePngSize(bytes) ??
        _parseJpegSize(bytes) ??
        _ImagePixelSize(
          _paintSize.width.round().clamp(1, 4096).toInt(),
          _paintSize.height.round().clamp(1, 4096).toInt(),
        );
  }

  _ImagePixelSize? _parsePngSize(Uint8List bytes) {
    const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length < 24) return null;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return null;
    }
    final data = ByteData.sublistView(bytes);
    return _ImagePixelSize(data.getUint32(16), data.getUint32(20));
  }

  _ImagePixelSize? _parseJpegSize(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      return null;
    }
    var offset = 2;
    while (offset + 9 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      final length = (bytes[offset + 2] << 8) + bytes[offset + 3];
      final isStartOfFrame = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isStartOfFrame && length >= 7 && offset + 8 < bytes.length) {
        final height = (bytes[offset + 5] << 8) + bytes[offset + 6];
        final width = (bytes[offset + 7] << 8) + bytes[offset + 8];
        if (width > 0 && height > 0) return _ImagePixelSize(width, height);
      }
      if (length < 2) return null;
      offset += 2 + length;
    }
    return null;
  }

  Uint8List _buildMaskPng(_ImagePixelSize source) {
    final paintSize = _paintSize.isEmpty
        ? Size(source.width.toDouble(), source.height.toDouble())
        : _paintSize;
    final scaleX = source.width / paintSize.width;
    final scaleY = source.height / paintSize.height;
    final strokeWidth =
        (28 * ((scaleX + scaleY) / 2)).clamp(1.0, 96.0).toDouble();
    final mask =
        img.Image(width: source.width, height: source.height, numChannels: 4)
          ..clear(img.ColorRgba8(0, 0, 0, 0));
    final color = img.ColorRgba8(255, 255, 255, 255);

    int scaleXToPixel(Offset point) =>
        (point.dx * scaleX).round().clamp(0, source.width - 1).toInt();
    int scaleYToPixel(Offset point) =>
        (point.dy * scaleY).round().clamp(0, source.height - 1).toInt();

    for (var i = 0; i < _points.length; i++) {
      final current = _points[i];
      if (current == null) continue;
      final previous = i == 0 ? null : _points[i - 1];
      if (previous == null) {
        img.fillCircle(
          mask,
          x: scaleXToPixel(current),
          y: scaleYToPixel(current),
          radius: (strokeWidth / 2).ceil(),
          color: color,
          antialias: true,
        );
      } else {
        img.drawLine(
          mask,
          x1: scaleXToPixel(previous),
          y1: scaleYToPixel(previous),
          x2: scaleXToPixel(current),
          y2: scaleYToPixel(current),
          thickness: strokeWidth,
          color: color,
          antialias: true,
        );
      }
    }

    return Uint8List.fromList(img.encodePng(mask));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = context.l10n;
    final instruction = _controller.text.trim();
    final hasMask = _points.whereType<Offset>().isNotEmpty;
    setState(() {
      _instructionError =
          instruction.isEmpty ? l10n.repaintInstructionRequired : null;
      _maskError = hasMask ? null : l10n.inpaintMaskRequired;
    });
    if (instruction.isEmpty || !hasMask) return;

    setState(() => _submitting = true);
    try {
      final source = _readSourceImageSize();
      final maskPng = _buildMaskPng(source);
      if (!mounted) return;
      Navigator.of(context).pop(
        _MaskEditResult(instruction: instruction, maskPng: maskPng),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _maskError = l10n.inpaintMaskCreateFailed;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final dialogWidth =
        (MediaQuery.sizeOf(context).width - 96).clamp(280.0, 560.0);
    final paintSize =
        Size(dialogWidth.toDouble(), dialogWidth.toDouble() * 9 / 16);
    _paintSize = paintSize;
    return AlertDialog(
      title: Text(l10n.inpaintTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.inpaintHint,
                  style: TextStyle(fontSize: 13, color: df.textMid)),
              const SizedBox(height: 12),
              SizedBox(
                width: paintSize.width,
                height: paintSize.height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: df.surfaceMuted),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(widget.imageAbsPath),
                          fit: BoxFit.fill,
                          errorBuilder: (context, error, stack) => Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: df.textTertiary),
                          ),
                        ),
                        GestureDetector(
                          key: const Key('mask-paint-area'),
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (details) =>
                              _addPoint(details.localPosition),
                          onPanUpdate: (details) =>
                              _addPoint(details.localPosition),
                          onPanEnd: (_) => setState(() {
                            if (_points.isNotEmpty && _points.last != null) {
                              _points.add(null);
                            }
                          }),
                          child: CustomPaint(
                            painter: _MaskPainter(points: _points),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_maskError != null) ...[
                const SizedBox(height: 6),
                Text(_maskError!,
                    style: TextStyle(fontSize: 12, color: df.danger)),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                minLines: 2,
                maxLines: 4,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l10n.repaintImageHint,
                  errorText: _instructionError,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _submitting
                      ? null
                      : () => setState(() {
                            _points.clear();
                            _maskError = null;
                          }),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 16),
                  label: Text(l10n.commonDelete),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton.icon(
          onPressed: _submitting ? null : _submit,
          icon: const Icon(Icons.gesture_rounded, size: 18),
          label: Text(l10n.inpaintAction),
        ),
      ],
    );
  }
}

class _MaskPainter extends CustomPainter {
  final List<Offset?> points;

  const _MaskPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 28;
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.72)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < points.length; i++) {
      final current = points[i];
      if (current == null) continue;
      final previous = i == 0 ? null : points[i - 1];
      if (previous == null) {
        canvas.drawCircle(current, paint.strokeWidth / 2, dotPaint);
      } else {
        canvas.drawLine(previous, current, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) =>
      !identical(points, oldDelegate.points) ||
      points.length != oldDelegate.points.length;
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

/// 连线中点的删除手柄（点击删除该连线）。
class _EdgeDeleteDot extends StatelessWidget {
  final VoidCallback onTap;
  final String tooltip;
  const _EdgeDeleteDot({required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: df.danger,
            border: Border.all(color: df.surface, width: 2),
          ),
          child: Icon(Icons.close, size: 12, color: df.surface),
        ),
      ),
    );
  }
}

/// 素材/分镜选图项（相对路径 + 展示名）。
class _PickItem {
  final String rel;
  final String label;
  const _PickItem({required this.rel, required this.label});
}

/// 素材库 / 分镜选图网格（点击某项返回其相对路径给调用方）。
class _LibraryPicker extends StatelessWidget {
  final Engine engine;
  final List<_PickItem> items;
  final String emptyText;
  const _LibraryPicker({
    required this.engine,
    required this.items,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(DFTokens.s24),
        child: Center(
          child: Text(emptyText,
              style: TextStyle(fontSize: 13, color: df.textTertiary)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s12),
      child: GridView.builder(
        shrinkWrap: true,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: items.length,
        itemBuilder: (c, i) {
          final it = items[i];
          return InkWell(
            onTap: () => Navigator.of(context).pop(it.rel),
            borderRadius: BorderRadius.circular(6),
            child: Column(children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                      color: df.surfaceMuted,
                      borderRadius: BorderRadius.circular(6)),
                  child: Image.file(
                    File(engine.mediaAbsPath(it.rel)),
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Icon(Icons.broken_image_outlined,
                        color: df.textTertiary),
                  ),
                ),
              ),
              Text(it.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10)),
            ]),
          );
        },
      ),
    );
  }
}
