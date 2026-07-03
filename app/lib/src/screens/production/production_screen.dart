// 制作画布（照抄 production/index.vue 主链结构，见移植参照 §1）：
// 剧集选择器 + 无限画布（script→scriptPlan→storyboardTable→storyboard→workbench 主链，
// assets 挂 script 下方）。scriptPlan 为 P5 占位卡片（Agent 体系待后续批次）；
// workbench 为紧凑摘要卡+入口按钮，打开全屏工作台（P4，见 workbench_screen.dart）。
// 移动端 <840：画布不适合窄屏平移操作，改为纵向 Tab 切换各节点内容（同功能不同呈现）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/assets.dart';
import '../../engine/compose_episode.dart';
import '../../engine/scripts.dart';
import '../../engine/storyboard.dart';
import '../../state/providers.dart';
import '../../theme/theme.dart';
import '../../theme/tokens.dart';
import '../../util/l10n_ext.dart';
import '../../widgets/df_canvas.dart';
import '../../widgets/df_empty.dart';
import 'image_flow_editor.dart';
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
class _CanvasLayout extends StatelessWidget {
  final int projectId;
  final ScriptRow script;
  const _CanvasLayout({required this.projectId, required this.script});

  @override
  Widget build(BuildContext context) {
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

    return DFCanvas(
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
          size: const Size(nodeW, 220),
          child: _StubNode(
              title: context.l10n.productionNodeScriptPlanTitle, batch: 'P5'),
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
  late final TabController _tab = TabController(length: 5, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(children: [
      TabBar(
        controller: _tab,
        isScrollable: true,
        tabs: [
          Tab(text: l10n.productionNodeScriptTitle),
          Tab(text: l10n.productionNodeAssetsTitle),
          Tab(text: l10n.productionNodeStoryboardTableTitle),
          Tab(text: l10n.productionNodeStoryboardTitle),
          Tab(text: l10n.workbenchTitle),
        ],
      ),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          _ScriptNode(script: widget.script),
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
  const _NodeHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: df.textPrimary,
      child: Text(title,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: df.surface)),
    );
  }
}

class _ScriptNode extends StatelessWidget {
  final ScriptRow script;
  const _ScriptNode({required this.script});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _NodeFrame(
      title: l10n.productionNodeScriptTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _NodeHeader(title: '${l10n.productionNodeScriptTitle} · ${script.name ?? ''}'),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: Text(script.content ?? '',
                  style: const TextStyle(fontSize: 12, height: 1.5)),
            ),
          ),
        ),
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

class _StoryboardTableNode extends ConsumerWidget {
  final int projectId;
  final int scriptId;
  const _StoryboardTableNode({required this.projectId, required this.scriptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final df = context.df;
    ref.watch(jobsGenerationProvider);
    final rows = ref.watch(engineProvider).storyboards(scriptId);
    return _NodeFrame(
      title: l10n.productionNodeStoryboardTableTitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _NodeHeader(title: l10n.productionNodeStoryboardTableTitle),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(l10n.productionStoryboardNotGenerated,
                      style: TextStyle(fontSize: 11, color: df.textTertiary)))
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: rows.length,
                  itemBuilder: (c, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'S${(i + 1).toString().padLeft(2, '0')}  ${rows[i].prompt ?? ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
        ),
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

class _StubNode extends StatelessWidget {
  final String title;
  final String batch;
  const _StubNode({required this.title, required this.batch});

  @override
  Widget build(BuildContext context) {
    final df = context.df;
    return _NodeFrame(
      title: title,
      child: Column(children: [
        _NodeHeader(title: title),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.hourglass_empty, color: df.textTertiary, size: 20),
              const SizedBox(height: 6),
              Text(context.l10n.shellComingSoon(batch),
                  style: TextStyle(fontSize: 11, color: df.textTertiary)),
            ]),
          ),
        ),
      ]),
    );
  }
}
