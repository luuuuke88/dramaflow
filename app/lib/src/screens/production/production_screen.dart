// 制作画布（照抄 production/index.vue 主链结构，见移植参照 §1）：
// 剧集选择器 + 无限画布（script→scriptPlan→storyboardTable→storyboard→workbench 主链，
// assets 挂 script 下方）。scriptPlan 为真实 Markdown 规划节点（见 script_plan_node.dart，
// 存 o_agentWorkData(key='scriptPlan')）；workbench 为紧凑摘要卡+入口按钮，打开全屏
// 工作台（P4，见 workbench_screen.dart）。右上角提供 Agent 对话入口：桌面右侧滑出面板、
// 移动端全屏对话（照抄 ToonFlow rightChatBox，见 canvas_chat_panel.dart）。
// 移动端 <840：画布不适合窄屏平移操作，改为纵向 Tab 切换各节点内容（同功能不同呈现）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/assets.dart';
import '../../engine/compose_episode.dart';
import '../../engine/scripts.dart';
import '../../engine/storyboard_table.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_adaptive_dialog.dart';
import '../../widgets/df_canvas.dart';
import '../../widgets/df_empty.dart';
import 'canvas_chat_panel.dart';
import 'image_flow_editor.dart';
import 'script_plan_node.dart';
import 'workbench_screen.dart';
import 'storyboard_canvas_node.dart';

class ProductionScreen extends ConsumerStatefulWidget {
  final int projectId;
  const ProductionScreen({super.key, required this.projectId});

  @override
  ConsumerState<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends ConsumerState<ProductionScreen> {
  int? _scriptId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scripts = ref.watch(engineProvider).scripts(widget.projectId);
    if (scripts.isEmpty) {
      return Center(
        child: DFEmpty(
          text: l10n.productionNoScripts,
          action: FilledButton(
            onPressed: () => context.go('/p/${widget.projectId}/script'),
            child: Text(l10n.productionGoToScripts),
          ),
        ),
      );
    }
    _scriptId ??= scripts.first.id;
    final script = scripts.firstWhere((s) => s.id == _scriptId,
        orElse: () => scripts.first);

    return Column(children: [
      _EpisodeBar(
        scripts: scripts,
        selectedId: script.id,
        onSelect: (id) => setState(() => _scriptId = id),
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, constraints) {
          return constraints.maxWidth >= 840
              ? _CanvasLayout(projectId: widget.projectId, script: script)
              : _MobileTabsLayout(projectId: widget.projectId, script: script);
        }),
      ),
    ]);
  }
}

class _EpisodeBar extends StatelessWidget {
  final List<ScriptRow> scripts;
  final int selectedId;
  final ValueChanged<int> onSelect;
  const _EpisodeBar(
      {required this.scripts, required this.selectedId, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: df.stroke))),
      child: Row(children: [
        Text(context.l10n.productionSelectEpisode,
            style: TextStyle(fontSize: 12, color: df.textSecondary)),
        const SizedBox(width: 10),
        Expanded(
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in scripts)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s.name ?? '#${s.id}',
                        style: const TextStyle(fontSize: 12)),
                    selected: s.id == selectedId,
                    onSelected: (_) => onSelect(s.id),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// 桌面画布布局：链式节点 + 贝塞尔边（位置每次构建重算，不落库，与 ToonFlow 主画布行为一致）。
/// 右上角工具栏含 Agent 对话入口，点击滑出右侧对话面板（照抄 ToonFlow rightChatBox）。
class _CanvasLayout extends StatefulWidget {
  final int projectId;
  final ScriptRow script;
  const _CanvasLayout({required this.projectId, required this.script});

  @override
  State<_CanvasLayout> createState() => _CanvasLayoutState();
}

class _CanvasLayoutState extends State<_CanvasLayout> {
  static const _chatPanelWidth = 380.0;
  bool _chatOpen = false;

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final script = widget.script;
    const gap = 60.0;
    const nodeW = 320.0;
    var x = 0.0;
    final scriptPos = Offset(x, 0);
    x += nodeW + gap;
    final planPos = Offset(x, 0);
    x += nodeW + gap;
    final tablePos = Offset(x, 0);
    x += nodeW + gap;
    final storyboardPos = Offset(x, 0);
    const storyboardW = 720.0;
    x += storyboardW + gap;
    final workbenchPos = Offset(x, 0);
    final assetsPos = Offset(scriptPos.dx, 460.0);

    final canvas = DFCanvas(
      fitOnInit: true,
      nodes: [
        DFCanvasNode(
          id: 'script',
          position: scriptPos,
          size: const Size(nodeW, 400),
          child: _ScriptNode(script: script),
        ),
        DFCanvasNode(
          id: 'scriptPlan',
          position: planPos,
          size: const Size(nodeW, 260),
          child: ScriptPlanNode(projectId: projectId),
        ),
        DFCanvasNode(
          id: 'assets',
          position: assetsPos,
          size: const Size(nodeW, 320),
          child: _AssetsNode(projectId: projectId, script: script),
        ),
        DFCanvasNode(
          id: 'storyboardTable',
          position: tablePos,
          size: const Size(nodeW, 400),
          child: _StoryboardTableNode(projectId: projectId, scriptId: script.id),
        ),
        DFCanvasNode(
          id: 'storyboard',
          position: storyboardPos,
          size: const Size(storyboardW, 620),
          child: _NodeFrame(
            title: context.l10n.productionNodeStoryboardTitle,
            child: StoryboardCanvasNode(projectId: projectId, scriptId: script.id),
          ),
        ),
        DFCanvasNode(
          id: 'workbench',
          position: workbenchPos,
          size: const Size(nodeW, 220),
          child: _WorkbenchNode(projectId: projectId, scriptId: script.id),
        ),
      ],
      edges: const [
        DFCanvasEdge(sourceId: 'script', targetId: 'assets'),
        DFCanvasEdge(sourceId: 'script', targetId: 'scriptPlan'),
        DFCanvasEdge(sourceId: 'scriptPlan', targetId: 'storyboardTable'),
        DFCanvasEdge(sourceId: 'storyboardTable', targetId: 'storyboard'),
        DFCanvasEdge(sourceId: 'storyboard', targetId: 'workbench'),
      ],
    );

    final df = context.df;
    return Stack(children: [
      Positioned.fill(child: canvas),
      // 右上角 Agent 对话入口（面板打开时隐藏，让位于面板头部的关闭按钮）。
      if (!_chatOpen)
        Positioned(
          top: 12,
          right: 12,
          child: FloatingActionButton.extended(
            heroTag: 'canvasChatToggle',
            onPressed: () => setState(() => _chatOpen = true),
            icon: const Icon(Icons.smart_toy_outlined),
            label: Text(context.l10n.canvasChatOpen),
          ),
        ),
      // 右侧滑出对话面板。
      AnimatedPositioned(
        duration: DFTokens.standard200,
        curve: DFTokens.curve,
        top: 0,
        bottom: 0,
        right: _chatOpen ? 0 : -_chatPanelWidth,
        width: _chatPanelWidth,
        child: Material(
          elevation: 8,
          color: df.surface,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: df.stroke)),
            ),
            child: _chatOpen
                ? CanvasChatPanel(
                    projectId: projectId,
                    onClose: () => setState(() => _chatOpen = false),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    ]);
  }
}

/// 移动端布局：纵向 Tab 切换（画布拖拽在窄屏不可用，同功能不同呈现）。
class _MobileTabsLayout extends StatefulWidget {
  final int projectId;
  final ScriptRow script;
  const _MobileTabsLayout({required this.projectId, required this.script});

  @override
  State<_MobileTabsLayout> createState() => _MobileTabsLayoutState();
}

class _MobileTabsLayoutState extends State<_MobileTabsLayout>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 6, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  /// 移动端 Agent 对话入口：全屏对话页（照抄 ToonFlow rightChatBox 的移动呈现）。
  void _openChat() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (c) => Scaffold(
          appBar: AppBar(title: Text(context.l10n.canvasChatTitle)),
          body: CanvasChatPanel(projectId: widget.projectId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(children: [
      Row(children: [
        Expanded(
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l10n.productionNodeScriptTitle),
              Tab(text: l10n.productionNodeScriptPlanTitle),
              Tab(text: l10n.productionNodeAssetsTitle),
              Tab(text: l10n.productionNodeStoryboardTableTitle),
              Tab(text: l10n.productionNodeStoryboardTitle),
              Tab(text: l10n.workbenchTitle),
            ],
          ),
        ),
        IconButton(
          tooltip: l10n.canvasChatOpen,
          icon: const Icon(Icons.smart_toy_outlined),
          onPressed: _openChat,
        ),
        const SizedBox(width: 4),
      ]),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          _ScriptNode(script: widget.script),
          ScriptPlanNode(projectId: widget.projectId),
          _AssetsNode(projectId: widget.projectId, script: widget.script),
          _StoryboardTableNode(
              projectId: widget.projectId, scriptId: widget.script.id),
          StoryboardCanvasNode(
              projectId: widget.projectId, scriptId: widget.script.id),
          _WorkbenchNode(
              projectId: widget.projectId, scriptId: widget.script.id),
        ]),
      ),
    ]);
  }
}

class _NodeFrame extends StatelessWidget {
  final String title;
  final Widget child;
  const _NodeFrame({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      decoration: BoxDecoration(
        color: df.surface,
        borderRadius: BorderRadius.circular(DFTokens.radiusCard),
        border: Border.all(color: df.stroke),
        boxShadow: DFTokens.cardRest,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _NodeHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onEdit;
  const _NodeHeader({required this.title, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      padding: EdgeInsets.fromLTRB(12, onEdit == null ? 8 : 4, onEdit == null ? 12 : 4, onEdit == null ? 8 : 4),
      color: df.textPrimary,
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: df.surface)),
        ),
        if (onEdit != null)
          IconButton(
            tooltip: context.l10n.commonEdit,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            icon: Icon(Icons.edit_outlined, size: 15, color: df.surface),
            onPressed: onEdit,
          ),
      ]),
    );
  }
}

/// 剧本节点（照抄 ToonFlow production script 节点）：展示剧本正文，头部提供
/// 编辑入口，弹出对话框改写名称/正文并经 engine.updateScript 持久化。
/// engine 无响应式，保存后 setState 重读预览。
class _ScriptNode extends ConsumerStatefulWidget {
  final ScriptRow script;
  const _ScriptNode({required this.script});

  @override
  ConsumerState<_ScriptNode> createState() => _ScriptNodeState();
}

class _ScriptNodeState extends ConsumerState<_ScriptNode> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // 保存后从引擎重读该剧本最新值（engine 无监听，需手动重查）。
    final script = ref
            .read(engineProvider)
            .scripts(widget.script.projectId)
            .where((s) => s.id == widget.script.id)
            .firstOrNull ??
        widget.script;
    return _NodeFrame(
      title: l10n.productionNodeScriptTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _NodeHeader(
          title: '${l10n.productionNodeScriptTitle} · ${script.name ?? ''}',
          onEdit: () => _openEditor(script),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _openEditor(script),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Text(script.content ?? '',
                    style: const TextStyle(fontSize: 12, height: 1.5)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openEditor(ScriptRow script) async {
    final saved = await showDFAdaptiveDialog<bool>(
      context,
      title: context.l10n.scriptNodeEditTitle,
      builder: (_) => _ScriptNodeEditor(script: script),
    );
    if (saved == true && mounted) setState(() {});
  }
}

class _ScriptNodeEditor extends ConsumerStatefulWidget {
  final ScriptRow script;
  const _ScriptNodeEditor({required this.script});

  @override
  ConsumerState<_ScriptNodeEditor> createState() => _ScriptNodeEditorState();
}

class _ScriptNodeEditorState extends ConsumerState<_ScriptNodeEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.script.name ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.script.content ?? '');

  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = context.l10n;
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.scriptNodeNameRequired)));
      return;
    }
    ref.read(engineProvider).updateScript(
          widget.script.id,
          name: _name.text.trim(),
          content: _content.text,
        );
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.scriptNodeSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: l10n.scriptNodeName,
            hintText: l10n.scriptNodeNamePlaceholder,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: DFTokens.s12),
        Flexible(
          child: TextField(
            controller: _content,
            minLines: 8,
            maxLines: 20,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              labelText: l10n.scriptNodeContent,
              hintText: l10n.scriptNodeContentPlaceholder,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: DFTokens.s12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(width: DFTokens.s8),
          FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
        ]),
      ]),
    );
  }
}

class _AssetsNode extends ConsumerWidget {
  final int projectId;
  final ScriptRow script;
  const _AssetsNode({required this.projectId, required this.script});

  /// 点击资产卡打开节点式编辑器（画布语境下的专属入口，区别于素材管理页的
  /// 简单生图对话框——照抄 ToonFlow：production 画布的 assets 节点点击资产
  /// 打开 editImage，assets/index.vue 列表页才用 generateImage 简版）。
  void _openEditor(BuildContext context, WidgetRef ref, AssetRow asset) {
    showImageFlowEditor(
      context,
      ref,
      projectId: projectId,
      flowId: asset.flowId,
      scriptId: script.id,
      seedReferenceRelPaths:
          asset.filePath != null ? [asset.filePath!] : const [],
      onApply: (rel, flowId) {
        ref.read(engineProvider).attachAssetImage(asset.id, rel, flowId: flowId);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    final ids = script.relatedAssets.map((a) => a.id).toList();
    final assets = ref.watch(engineProvider).assetsByIds(ids);
    return _NodeFrame(
      title: l10n.productionNodeAssetsTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _NodeHeader(title: l10n.productionNodeAssetsTitle),
        Expanded(
          child: assets.isEmpty
              ? Center(
                  child: Text(l10n.scriptAddNoAssets,
                      style: TextStyle(fontSize: 11, color: df.textTertiary)))
              : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6),
                  itemCount: assets.length,
                  itemBuilder: (c, i) {
                    final a = assets[i];
                    return GestureDetector(
                      onTap: () => _openEditor(context, ref, a),
                      child: Column(children: [
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                                color: df.surfaceMuted,
                                borderRadius: BorderRadius.circular(6)),
                            child: a.filePath != null
                                ? Image.file(
                                    File(ref
                                        .read(engineProvider)
                                        .mediaAbsPath(a.filePath!)),
                                    fit: BoxFit.cover,
                                    errorBuilder: (c, e, s) => Icon(
                                        Icons.broken_image_outlined,
                                        size: 18,
                                        color: df.textTertiary))
                                : Icon(Icons.image_outlined,
                                    size: 18, color: df.textTertiary),
                          ),
                        ),
                        Text(a.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10)),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

/// 分镜表节点（照抄 ToonFlow production storyboardTable：可编辑 Markdown 文档，
/// 剧集级，存 o_agentWorkData(key='storyboardTable')）。头部提供编辑入口，弹出
/// 对话框改写并持久化（复用 scriptPlan 的持久化+重读模式）。engine 无响应式，
/// 保存后 setState 重读预览。
class _StoryboardTableNode extends ConsumerStatefulWidget {
  final int projectId;
  final int scriptId;
  const _StoryboardTableNode({required this.projectId, required this.scriptId});

  @override
  ConsumerState<_StoryboardTableNode> createState() =>
      _StoryboardTableNodeState();
}

class _StoryboardTableNodeState extends ConsumerState<_StoryboardTableNode> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final df = context.df;
    final markdown = ref
        .read(engineProvider)
        .storyboardTable(widget.projectId, widget.scriptId);
    final hasTable = markdown.trim().isNotEmpty;
    return _NodeFrame(
      title: l10n.productionNodeStoryboardTableTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _NodeHeader(
          title: l10n.productionNodeStoryboardTableTitle,
          onEdit: () => _openEditor(markdown),
        ),
        Expanded(
          child: InkWell(
            onTap: () => _openEditor(markdown),
            child: hasTable
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: SingleChildScrollView(
                      child: Text(markdown,
                          style: const TextStyle(fontSize: 12, height: 1.5)),
                    ),
                  )
                : Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.table_rows_outlined,
                          color: df.textTertiary, size: 22),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(l10n.storyboardTableEmpty,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12, color: df.textTertiary)),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () => _openEditor(markdown),
                        icon: const Icon(Icons.edit_note, size: 16),
                        label: Text(l10n.storyboardTableWrite,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ]),
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openEditor(String current) async {
    final saved = await showDFAdaptiveDialog<bool>(
      context,
      title: context.l10n.storyboardTableEditTitle,
      builder: (_) => _StoryboardTableEditor(
        projectId: widget.projectId,
        scriptId: widget.scriptId,
        initial: current,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }
}

class _StoryboardTableEditor extends ConsumerStatefulWidget {
  final int projectId;
  final int scriptId;
  final String initial;
  const _StoryboardTableEditor({
    required this.projectId,
    required this.scriptId,
    required this.initial,
  });

  @override
  ConsumerState<_StoryboardTableEditor> createState() =>
      _StoryboardTableEditorState();
}

class _StoryboardTableEditorState
    extends ConsumerState<_StoryboardTableEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref.read(engineProvider).saveStoryboardTable(
        widget.projectId, widget.scriptId, _controller.text);
    if (!mounted) return;
    final l10n = context.l10n;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.storyboardTableSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(DFTokens.s16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: TextField(
            controller: _controller,
            minLines: 8,
            maxLines: 20,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: l10n.storyboardTableEditHint,
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: DFTokens.s12),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.commonCancel),
          ),
          const SizedBox(width: DFTokens.s8),
          FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
        ]),
      ]),
    );
  }
}

class _WorkbenchNode extends ConsumerWidget {
  final int projectId;
  final int scriptId;
  const _WorkbenchNode({required this.projectId, required this.scriptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final engine = ref.watch(engineProvider);
    final paths = engine.orderedSelectedVideoPaths(scriptId);
    final ready = paths.where((p) => p != null && p.isNotEmpty).length;
    return _NodeFrame(
      title: l10n.workbenchTitle,
      child: Column(children: [
        _NodeHeader(title: l10n.workbenchTitle),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.video_library_outlined, size: 28, color: df.primary),
              const SizedBox(height: 8),
              Text('$ready / ${paths.length}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(l10n.workbenchSelected,
                  style: TextStyle(fontSize: 11, color: df.textTertiary)),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: paths.isEmpty
                    ? null
                    : () => showWorkbench(context, ref,
                        projectId: projectId, scriptId: scriptId),
                icon: const Icon(Icons.open_in_new, size: 14),
                label: Text(l10n.workbenchOpen,
                    style: const TextStyle(fontSize: 12)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

